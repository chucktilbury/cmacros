import system as Sys
import cli as Cli

class Macro {
    String name
    String body
    String file
    int64 line
    int64 column
    list parameters
    bool functionLike

    Macro(String macroName, String replacement, String sourceFile, int64 sourceLine,
          int64 sourceColumn,
          list parameterNames, bool takesParameters) {
        name = macroName
        body = replacement
        file = sourceFile
        line = sourceLine
        column = sourceColumn
        parameters = parameterNames
        functionLike = takesParameters
    }
}

class Arguments {
    list values
    int64 end
    bool valid

    Arguments(list parsedValues, int64 next, bool succeeded) {
        values = parsedValues
        end = next
        valid = succeeded
    }
}

class Operator {
    int64 index
    String name

    Operator(int64 position, String token) {
        index = position
        name = token
    }
}

class LiteralValue {
    String value
    int64 end
    bool valid

    LiteralValue(String decoded, int64 next, bool succeeded) {
        value = decoded
        end = next
        valid = succeeded
    }
}

class Processor {
    list macros
    list includePaths
    list cachedPaths
    list cachedContents
    list currentImports
    list currentTrace
    bool failed
    int64 work
    int64 totalWork
    int64 outputLimit
    String conditionFile
    int64 conditionLine
    int64 conditionColumn
    bool keepComments
    Sys.StandardIO io

    Processor(list paths) {
        macros = []
        includePaths = paths
        cachedPaths = []
        cachedContents = []
        currentImports = []
        currentTrace = []
        failed = false
        work = 0
        totalWork = 0
        outputLimit = 7000000
        conditionFile = ""
        conditionLine = 1
        conditionColumn = 1
        keepComments = false
        io = Sys.System().io()
    }

    int64 byte(String text, int64 index) {
        if (index < 0 or index >= text.length) {
            return(-1)
        }
        return(int64(text[index]))
    }

    int64 utf8Width(int64 firstByte) {
        if (firstByte >= 240) {
            return(4)
        }
        if (firstByte >= 224) {
            return(3)
        }
        if (firstByte >= 192) {
            return(2)
        }
        return(1)
    }

    bool nameStart(int64 value) {
        return((value >= 65 and value <= 90) or (value >= 97 and value <= 122) or value == 95)
    }

    bool namePart(int64 value) {
        return(nameStart(value) or (value >= 48 and value <= 57))
    }

    bool space(int64 value) {
        return(value == 32 or value == 9 or value == 10 or value == 13 or value == 12 or value == 11)
    }

    int64 skipSpace(String text, int64 index) {
        while (index < text.length and space(byte(text, index))) {
            index = index + 1
        }
        return(index)
    }

    int64 skipHorizontal(String text, int64 index) {
        while (index < text.length and (byte(text, index) == 32 or byte(text, index) == 9 or byte(text, index) == 13)) {
            index = index + 1
        }
        return(index)
    }

    int64 lineAfter(String text, int64 fromIndex, int64 end, int64 startLine) {
        int64 line = startLine
        int64 cursor = fromIndex
        while (cursor < end and cursor < text.length) {
            if (byte(text, cursor) == 10) {
                line = line + 1
            }
            cursor = cursor + 1
        }
        return(line)
    }

    int64 columnAfter(String text, int64 fromIndex, int64 end, int64 startColumn) {
        int64 column = startColumn
        int64 cursor = fromIndex
        while (cursor < end and cursor < text.length) {
            int64 current = byte(text, cursor)
            if (current == 10) {
                column = 1
                cursor = cursor + 1
            } else {
                int64 width = utf8Width(current)
                if (current < 128 or current >= 192) {
                    column = column + 1
                }
                cursor = cursor + width
            }
        }
        return(column)
    }

    String readName(String text, int64 first, int64 last) {
        int64 end = first
        while (end < last and namePart(byte(text, end))) {
            end = end + 1
        }
        return(byteSpan(text, first, end))
    }

    int64 nameEnd(String text, int64 first) {
        int64 end = first
        while (end < text.length and namePart(byte(text, end))) {
            end = end + 1
        }
        return(end)
    }

    bool validName(String name) {
        if (name.length == 0 or not nameStart(byte(name, 0))) {
            return(false)
        }
        int64 index = 1
        while (index < name.length) {
            if (not namePart(byte(name, index))) {
                return(false)
            }
            index = index + 1
        }
        return(true)
    }

    Macro findMacro(String name) {
        int64 index = 0
        while (index < macros.length) {
            Macro macro = macros[index] as Macro
            if (macro.name.equals(name)) {
                return(macro)
            }
            index = index + 1
        }
        return(null)
    }

    void removeDefinition(String name, String file, int64 line, int64 column) {
        if (not validName(name)) {
            report(1000, file, line, column,
                   format("invalid macro name '{}'", name))
            return
        }
        int64 index = 0
        while (index < macros.length) {
            Macro macro = macros[index] as Macro
            if (macro.name.equals(name)) {
                macros.remove(index..index)
                return
            }
            index = index + 1
        }
        report(1000, file, line, column,
               format("macro '{}' is not defined", name))
    }

    bool isDefinednessOperand(String expression) {
        String value = expression.trim()
        if (value.length == 0 or value.startsWith("@")) {
            return(false)
        }
        if (decimalNumber(value)) {
            return(false)
        }
        String upper = value.toUpper()
        if (upper.equals("TRUE") or upper.equals("FALSE")) {
            return(false)
        }
        if (nameStart(byte(value, 0)) and nameEnd(value, 0) == value.length) {
            return(true)
        }
        return(false)
    }

    bool isAtOperand(String expression) {
        return(expression.trim().startsWith("@"))
    }

    int64 findParameter(list names, String name) {
        int64 index = 0
        while (index < names.length) {
            String current = names[index] as String
            if (current.equals(name)) {
                return(index)
            }
            index = index + 1
        }
        return(-1)
    }

    void report(int64 code, String file, int64 line, int64 column, String message) {
        if (failed) {
            return
        }
        failed = true
        io.writeErrorLine(format(
            "cmacros: error[CMACRO{:04}]: {}:{}:{}: {}",
            code, file, line, column, message))
        int64 importIndex = 0
        while (importIndex < currentImports.length) {
            String imported = currentImports[importIndex] as String
            io.writeErrorLine(format("cmacros: note: imported from '{}'", imported))
            importIndex = importIndex + 1
        }
        int64 traceIndex = 0
        while (traceIndex < currentTrace.length) {
            String frame = currentTrace[traceIndex] as String
            io.writeErrorLine(format("cmacros: note: {}", frame))
            traceIndex = traceIndex + 1
        }
    }

    void conditionError(String message) {
        report(1009, conditionFile, conditionLine, conditionColumn, message)
    }

    void cacheSource(String path, String content) {
        cachedPaths.append(path)
        cachedContents.append(content)
    }

    String readFile(String path, int64 line) {
        int64 cacheIndex = 0
        while (cacheIndex < cachedPaths.length) {
            String cachedPath = cachedPaths[cacheIndex] as String
            if (cachedPath.equals(path)) {
                return(cachedContents[cacheIndex] as String)
            }
            cacheIndex = cacheIndex + 1
        }
        if (path.equals("<stdin>")) {
            report(2000, path, line, 1, "stdin source was not loaded")
            return("")
        }
        int64 size = Sys.FileSystem().fileSize(path)
        if (size > 16777216) {
            report(2001, path, line, 1, "input exceeds the 16 MiB source limit")
            return("")
        }
        String content = ""
        try {
            Sys.File input = Sys.File(path, "rb")
            content = input.readAll()
            input.close()
        } except() as message {
            report(2000, path, line, 1, format("cannot read input: {}", message))
        }
        if (not failed) {
            cacheSource(path, content)
        }
        return(content)
    }

    int64 definitionCount() {
        return(macros.length)
    }

    String resolveImport(String currentFile, String requested) {
        Sys.FileSystem fs = Sys.FileSystem()
        String local = fs.join(fs.dirname(currentFile), requested)
        if (fs.isFile(local)) {
            return(fs.absolutePath(local))
        }
        if (fs.isFile(format("{}.txt", local))) {
            return(fs.absolutePath(format("{}.txt", local)))
        }
        int64 index = 0
        while (index < includePaths.length) {
            String directory = includePaths[index] as String
            String candidate = fs.join(directory, requested)
            if (fs.isFile(candidate)) {
                return(fs.absolutePath(candidate))
            }
            if (fs.isFile(format("{}.txt", candidate))) {
                return(fs.absolutePath(format("{}.txt", candidate)))
            }
            index = index + 1
        }
        return("")
    }

    bool inList(list values, String name) {
        int64 index = 0
        while (index < values.length) {
            String value = values[index] as String
            if (value.equals(name)) {
                return(true)
            }
            index = index + 1
        }
        return(false)
    }

    String processFile(String file, list imports, list active, int64 depth) {
        list parentImports = currentImports
        currentImports = imports
        if (failed) {
            currentImports = parentImports
            return("")
        }
        if (depth > 128) {
            report(2002, file, 1, 1, "maximum import nesting depth (128) exceeded")
            currentImports = parentImports
            return("")
        }
        String canonical = file
        if (not file.equals("<stdin>")) {
            canonical = Sys.FileSystem().absolutePath(file)
            if (canonical.length == 0) {
                report(2000, file, 1, 1, "cannot resolve source path")
                currentImports = parentImports
                return("")
            }
        }
        if (inList(imports, canonical)) {
            report(2003, file, 1, 1, "import cycle detected")
            currentImports = parentImports
            return("")
        }
        list nestedImports = []
        int64 importIndex = 0
        while (importIndex < imports.length) {
            nestedImports.append(imports[importIndex])
            importIndex = importIndex + 1
        }
        nestedImports.append(canonical)
        currentImports = nestedImports
        String content = readFile(canonical, 1)
        String output = processText(canonical, content, 1, 1, [], [], active,
                                    nestedImports, depth)
        currentImports = parentImports
        return(output)
    }

    Arguments parseArguments(String text, int64 open) {
        list result = []
        int64 index = open + 1
        int64 valueStart = index
        int64 parens = 0
        int64 brackets = 0
        int64 braces = 0
        int64 quote = 0
        bool escaped = false
        bool finished = false
        while (index < text.length and not finished) {
            int64 current = byte(text, index)
            if (quote != 0) {
                if (escaped) {
                    escaped = false
                } else {
                    if (current == 92) {
                        escaped = true
                    } else {
                        if (current == quote) {
                            quote = 0
                        }
                    }
                }
            } else {
                if (current == 34 or current == 39) {
                    quote = current
                } else {
                    if (current == 40) {
                        parens = parens + 1
                    } else {
                        if (current == 41) {
                            if (parens == 0 and brackets == 0 and braces == 0) {
                                String value = byteSpan(text, valueStart, index).trim()
                                if (value.length > 0 or result.length > 0) {
                                    if (not validArgumentLiteral(value)) {
                                        return(Arguments([], open, false))
                                    }
                                    result.append(unquote(value))
                                }
                                index = index + 1
                                finished = true
                                continue
                            }
                            parens = parens - 1
                        } else {
                            if (current == 91) {
                                brackets = brackets + 1
                            } else {
                                if (current == 93) {
                                    brackets = brackets - 1
                                } else {
                                    if (current == 123) {
                                        braces = braces + 1
                                    } else {
                                        if (current == 125) {
                                            braces = braces - 1
                                        } else {
                                            if (current == 44 and parens == 0 and brackets == 0 and braces == 0) {
                                                String value = byteSpan(text, valueStart, index).trim()
                                                if (not validArgumentLiteral(value)) {
                                                    return(Arguments([], open, false))
                                                }
                                                result.append(unquote(value))
                                                valueStart = index + 1
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            index = index + 1
        }
        if (not finished) {
            return(Arguments([], open, false))
        }
        if (quote != 0 or parens != 0 or brackets != 0 or braces != 0) {
            return(Arguments([], open, false))
        }
        return(Arguments(result, index, true))
    }

    bool validArgumentLiteral(String value) {
        if (value.length > 0 and (byte(value, 0) == 34 or byte(value, 0) == 39)) {
            LiteralValue parsed = parseLiteral(value, 0)
            return(parsed.valid and parsed.end == value.length)
        }
        return(true)
    }

    String unquote(String value) {
        if (value.length >= 2 and ((byte(value, 0) == 34 and byte(value, value.length - 1) == 34) or (byte(value, 0) == 39 and byte(value, value.length - 1) == 39))) {
            LiteralValue decoded = parseLiteral(value, 0)
            if (decoded.valid) {
                return(decoded.value)
            }
        }
        return(value)
    }

    int64 hexValue(int64 value) {
        if (value >= 48 and value <= 57) {
            return(value - 48)
        }
        if (value >= 65 and value <= 70) {
            return(value - 55)
        }
        if (value >= 97 and value <= 102) {
            return(value - 87)
        }
        return(-1)
    }

    LiteralValue parseLiteral(String text, int64 open) {
        int64 quote = byte(text, open)
        if (quote != 34 and quote != 39) {
            return(LiteralValue("", open, false))
        }
        String result = ""
        int64 index = open + 1
        while (index < text.length) {
            int64 current = byte(text, index)
            if (current == quote) {
                return(LiteralValue(result, index + 1, true))
            }
            if (current == 92) {
                index = index + 1
                if (index >= text.length) {
                    return(LiteralValue("", open, false))
                }
                int64 escaped = byte(text, index)
                if (escaped == 110) {
                    result.append(format("{:c}", 10))
                } else {
                    if (escaped == 114) {
                        result.append(format("{:c}", 13))
                    } else {
                        if (escaped == 116) {
                            result.append(format("{:c}", 9))
                        } else {
                            if (escaped == 97) {
                                result.append(format("{:c}", 7))
                            } else {
                                if (escaped == 98) {
                                    result.append(format("{:c}", 8))
                                } else {
                                    if (escaped == 102) {
                                        result.append(format("{:c}", 12))
                                    } else {
                                        if (escaped == 118) {
                                            result.append(format("{:c}", 11))
                                        } else {
                                            if (escaped == 101) {
                                                result.append(format("{:c}", 27))
                                            } else {
                                                if (escaped == 120) {
                                                    if (index + 2 >= text.length) {
                                                        return(LiteralValue("", open, false))
                                                    }
                                                    int64 high = hexValue(byte(text, index + 1))
                                                    int64 low = hexValue(byte(text, index + 2))
                                                    if (high < 0 or low < 0) {
                                                        return(LiteralValue("", open, false))
                                                    }
                                                    result.append(format("{:c}", high * 16 + low))
                                                    index = index + 2
                                                } else {
                                                    result.append(byteSpan(text, index, index + 1))
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                index = index + 1
            } else {
                int64 width = utf8Width(current)
                result.append(byteSpan(text, index, index + width))
                index = index + width
            }
        }
        return(LiteralValue("", open, false))
    }

    bool wordBoundary(String text, int64 index) {
        if (index < 0 or index >= text.length) {
            return(true)
        }
        int64 value = byte(text, index)
        return(space(value) or value == 40 or value == 41)
    }

    int64 operatorPriority(String operator) {
        String upper = operator.toUpper()
        if (upper.equals("OR") or operator.equals("||")) {
            return(1)
        }
        if (upper.equals("AND") or operator.equals("&&")) {
            return(2)
        }
        if (upper.equals("==") or operator.equals("!=") or upper.equals("EQ") or upper.equals("NEQ")) {
            return(3)
        }
        if (operator.equals("<") or operator.equals(">") or operator.equals("<=") or operator.equals(">=") or upper.equals("LT") or upper.equals("GT") or upper.equals("LTE") or upper.equals("GTE")) {
            return(4)
        }
        return(0)
    }

    String operatorAt(String text, int64 index) {
        if (index + 1 < text.length) {
            String pair = byteSpan(text, index, index + 2)
            if (pair.equals("||") or pair.equals("&&") or pair.equals("==") or pair.equals("!=") or pair.equals("<=") or pair.equals(">=")) {
                return(pair)
            }
        }
        int64 remaining = text.length - index
        if (remaining >= 3) {
            String word = byteSpan(text, index, index + 3).toUpper()
            if ((word.equals("AND") or word.equals("NEQ") or word.equals("LTE") or word.equals("GTE")) and wordBoundary(text, index - 1) and wordBoundary(text, index + 3)) {
                return(word)
            }
        }
        if (remaining >= 2) {
            String word = byteSpan(text, index, index + 2).toUpper()
            if ((word.equals("OR") or word.equals("EQ") or word.equals("LT") or word.equals("GT")) and wordBoundary(text, index - 1) and wordBoundary(text, index + 2)) {
                return(word)
            }
        }
        if (byteSpan(text, index, index + 1).equals("<") or byteSpan(text, index, index + 1).equals(">")) {
            return(byteSpan(text, index, index + 1))
        }
        return("")
    }

    Operator findOperator(String expression, int64 wantedPriority) {
        int64 parens = 0
        int64 index = 0
        int64 quote = 0
        bool escaped = false
        Operator found = Operator(-1, "")
        while (index < expression.length) {
            int64 current = byte(expression, index)
            if (quote != 0) {
                if (escaped) {
                    escaped = false
                } else {
                    if (current == 92) {
                        escaped = true
                    } else {
                        if (current == quote) {
                            quote = 0
                        }
                    }
                }
            } else {
                if (current == 34 or current == 39) {
                    quote = current
                } else {
                    if (current == 40) {
                        parens = parens + 1
                    } else {
                        if (current == 41) {
                            parens = parens - 1
                        } else {
                            if (parens == 0) {
                                String operator = operatorAt(expression, index)
                                if (operatorPriority(operator) == wantedPriority) {
                                    found = Operator(index, operator)
                                }
                            }
                        }
                    }
                }
            }
            index = index + 1
        }
        return(found)
    }

    bool wrapsWholeExpression(String expression) {
        if (expression.length < 2 or byte(expression, 0) != 40 or byte(expression, expression.length - 1) != 41) {
            return(false)
        }
        int64 depth = 0
        int64 index = 0
        int64 quote = 0
        bool escaped = false
        while (index < expression.length) {
            int64 current = byte(expression, index)
            if (quote != 0) {
                if (escaped) {
                    escaped = false
                } else {
                    if (current == 92) {
                        escaped = true
                    } else {
                        if (current == quote) {
                            quote = 0
                        }
                    }
                }
            } else {
                if (current == 34 or current == 39) {
                    quote = current
                } else {
                    if (current == 40) {
                        depth = depth + 1
                    } else {
                        if (current == 41) {
                            depth = depth - 1
                            if (depth == 0 and index < expression.length - 1) {
                                return(false)
                            }
                        }
                    }
                }
            }
            index = index + 1
        }
        return(depth == 0)
    }

    bool decimalNumber(String value) {
        if (value.length == 0) {
            return(false)
        }
        int64 index = 0
        if (byte(value, 0) == 45 or byte(value, 0) == 43) {
            index = 1
        }
        if (index == value.length) {
            return(false)
        }
        while (index < value.length) {
            if (byte(value, index) < 48 or byte(value, index) > 57) {
                return(false)
            }
            index = index + 1
        }
        return(true)
    }

    bool decimalZero(String value) {
        int64 index = 0
        if (byte(value, 0) == 45 or byte(value, 0) == 43) {
            index = 1
        }
        while (index < value.length) {
            if (byte(value, index) != 48) {
                return(false)
            }
            index = index + 1
        }
        return(true)
    }

    int64 compareDecimals(String left, String right) {
        bool leftNegative = byte(left, 0) == 45
        bool rightNegative = byte(right, 0) == 45
        int64 leftStart = 0
        int64 rightStart = 0
        if (leftNegative or byte(left, 0) == 43) {
            leftStart = 1
        }
        if (rightNegative or byte(right, 0) == 43) {
            rightStart = 1
        }
        while (leftStart < left.length - 1 and byte(left, leftStart) == 48) {
            leftStart = leftStart + 1
        }
        while (rightStart < right.length - 1 and byte(right, rightStart) == 48) {
            rightStart = rightStart + 1
        }
        int64 leftLength = left.length - leftStart
        int64 rightLength = right.length - rightStart
        int64 magnitude = 0
        if (leftLength < rightLength) {
            magnitude = -1
        } else {
            if (leftLength > rightLength) {
                magnitude = 1
            } else {
                int64 index = 0
                while (index < leftLength and magnitude == 0) {
                    int64 leftDigit = byte(left, leftStart + index)
                    int64 rightDigit = byte(right, rightStart + index)
                    if (leftDigit < rightDigit) {
                        magnitude = -1
                    } else {
                        if (leftDigit > rightDigit) {
                            magnitude = 1
                        }
                    }
                    index = index + 1
                }
            }
        }
        if (leftNegative and not rightNegative) {
            return(-1)
        }
        if (not leftNegative and rightNegative) {
            return(1)
        }
        if (leftNegative) {
            return(-magnitude)
        }
        return(magnitude)
    }

    bool valueTruth(String value) {
        String trimmed = value.trim()
        if (trimmed.length == 0) {
            return(false)
        }
        if (decimalNumber(trimmed)) {
            return(not decimalZero(trimmed))
        }
        return(true)
    }

    bool evalCondition(String expression, int64 recursion) {
        if (recursion > 128) {
            conditionError("conditional expression nesting limit (128) exceeded")
            return(false)
        }
        String value = expression.trim()
        if (value.length == 0) {
            conditionError("empty conditional expression or operand")
            return(false)
        }
        int64 nesting = 0
        int64 scan = 0
        int64 quote = 0
        bool escaped = false
        while (scan < value.length) {
            int64 current = byte(value, scan)
            if (quote != 0) {
                if (escaped) {
                    escaped = false
                } else {
                    if (current == 92) {
                        escaped = true
                    } else {
                        if (current == quote) {
                            quote = 0
                        }
                    }
                }
            } else {
                if (current == 34 or current == 39) {
                    quote = current
                } else {
                    if (current == 40) {
                        nesting = nesting + 1
                    } else {
                        if (current == 41) {
                            nesting = nesting - 1
                            if (nesting < 0) {
                                conditionError(
                                    "unbalanced parentheses in conditional expression")
                                return(false)
                            }
                        }
                    }
                }
            }
            scan = scan + 1
        }
        if (nesting != 0) {
            conditionError("unbalanced parentheses in conditional expression")
            return(false)
        }
        while (wrapsWholeExpression(value)) {
            value = byteSpan(value, 1, value.length - 1).trim()
        }
        Operator operator = findOperator(value, 1)
        if (operator.index >= 0) {
            bool left = evalCondition(byteSpan(value, 0, operator.index), recursion + 1)
            bool right = evalCondition(byteSpan(value, operator.index + operator.name.length, value.length), recursion + 1)
            return(left or right)
        }
        operator = findOperator(value, 2)
        if (operator.index >= 0) {
            bool left = evalCondition(byteSpan(value, 0, operator.index), recursion + 1)
            bool right = evalCondition(byteSpan(value, operator.index + operator.name.length, value.length), recursion + 1)
            return(left and right)
        }
        operator = findOperator(value, 3)
        if (operator.index >= 0) {
            String left = byteSpan(value, 0, operator.index).trim()
            String right = byteSpan(value, operator.index + operator.name.length, value.length).trim()
            if (left.length == 0 or right.length == 0) {
                conditionError("comparison operator requires two operands")
                return(false)
            }
            return(compareCondition(left, right, operator.name))
        }
        operator = findOperator(value, 4)
        if (operator.index >= 0) {
            String left = byteSpan(value, 0, operator.index).trim()
            String right = byteSpan(value, operator.index + operator.name.length, value.length).trim()
            if (left.length == 0 or right.length == 0) {
                conditionError("comparison operator requires two operands")
                return(false)
            }
            return(compareCondition(left, right, operator.name))
        }
        if (value.startsWith("!")) {
            if (value.length == 1) {
                conditionError("unary ! requires an operand")
                return(false)
            }
            return(not evalCondition(byteSpan(value, 1, value.length), recursion + 1))
        }
        if (value.toUpper().startsWith("NOT ")) {
            return(not evalCondition(byteSpan(value, 4, value.length), recursion + 1))
        }
        if (value.toUpper().equals("TRUE")) {
            return(true)
        }
        if (value.toUpper().equals("FALSE")) {
            return(false)
        }
        if (value.startsWith("@")) {
            return(atReferenceDefinedNonempty(value, recursion + 1))
        }
        if (decimalNumber(value)) {
            return(valueTruth(value))
        }
        if (value.length > 0 and nameStart(byte(value, 0)) and nameEnd(value, 0) == value.length) {
            return(findMacro(value) != null)
        }
        conditionError("invalid token in conditional expression")
        return(false)
    }

    bool atReferenceDefinedNonempty(String expression, int64 recursion) {
        String value = expression.trim()
        int64 end = nameEnd(value, 1)
        if (end == 1) {
            conditionError("expected a macro name after @")
            return(false)
        }
        String name = byteSpan(value, 1, end)
        Macro macro = findMacro(name)
        if (macro == null) {
            return(false)
        }
        String expanded = resolveConditionValue(value, recursion)
        if (failed) {
            return(false)
        }
        return(expanded.length > 0)
    }

    String resolveConditionValue(String expression, int64 recursion) {
        String value = expression.trim()
        if (value.startsWith("@")) {
            int64 end = nameEnd(value, 1)
            if (end == 1) {
                conditionError("expected a macro name after @")
                return("")
            }
            String name = byteSpan(value, 1, end)
            Macro macro = findMacro(name)
            int64 cursor = skipHorizontal(value, end)
            list arguments = []
            int64 afterReference = end
            if (cursor < value.length) {
                if (byte(value, cursor) != 40 or macro == null or not macro.functionLike) {
                    conditionError("invalid text after macro reference in conditional expression")
                    return("")
                }
                Arguments parsed = parseArguments(value, cursor)
                if (not parsed.valid or parsed.end != value.length) {
                    conditionError("invalid macro argument list in conditional expression")
                    return("")
                }
                arguments = parsed.values
                afterReference = parsed.end
            } else {
                if (macro != null and macro.functionLike and macro.parameters.length > 0) {
                    conditionError(format("macro '{}' requires an argument list", name))
                    return("")
                }
            }
            if (macro == null) {
                return("")
            }
            if (arguments.length != macro.parameters.length) {
                conditionError(format("macro '{}' expects {} argument(s), got {}",
                                      name, macro.parameters.length, arguments.length))
                return("")
            }
            list active = [name]
            list parentTrace = currentTrace
            list nestedTrace = []
            int64 traceIndex = 0
            while (traceIndex < currentTrace.length) {
                nestedTrace.append(currentTrace[traceIndex])
                traceIndex = traceIndex + 1
            }
            nestedTrace.append(format(
                "expanded macro @{} in condition at {}:{} (defined at {}:{})",
                name, conditionFile, conditionLine, macro.file, macro.line))
            currentTrace = nestedTrace
            String expanded = processText(macro.file, macro.body, macro.line,
                macro.column, macro.parameters, arguments, active, currentImports,
                recursion + 1).trim()
            currentTrace = parentTrace
            return(expanded)
        }
        if (decimalNumber(value)) {
            return(value)
        }
        if (value.length > 0 and nameStart(byte(value, 0))) {
            if (nameEnd(value, 0) != value.length) {
                conditionError("invalid token in conditional expression")
                return("")
            }
            Macro macro = findMacro(value)
            if (macro != null) {
                return("1")
            }
            return("0")
        }
        conditionError("invalid token in conditional expression")
        return("")
    }

    bool compareCondition(String leftExpression, String rightExpression, String operator) {
        bool leftDefinedness = isDefinednessOperand(leftExpression)
        bool rightDefinedness = isDefinednessOperand(rightExpression)
        bool leftAt = isAtOperand(leftExpression)
        bool rightAt = isAtOperand(rightExpression)
        if ((leftAt and rightDefinedness) or (leftDefinedness and rightAt)) {
            conditionError("cannot mix @ and bare names in a comparison")
            return(false)
        }
        if (leftDefinedness != rightDefinedness) {
            conditionError("cannot mix bare names and value operands in a comparison")
            return(false)
        }
        String upper = operator.toUpper()
        bool equality = upper.equals("==") or upper.equals("EQ") or upper.equals("!=") or upper.equals("NEQ")
        if (leftDefinedness and rightDefinedness) {
            if (not equality) {
                conditionError("bare names only support == and != comparisons")
                return(false)
            }
            bool leftDefined = findMacro(leftExpression.trim()) != null
            bool rightDefined = findMacro(rightExpression.trim()) != null
            bool equal = leftDefined == rightDefined
            if (upper.equals("==") or upper.equals("EQ")) {
                return(equal)
            }
            return(not equal)
        }
        String left = resolveConditionValue(leftExpression, 0)
        String right = resolveConditionValue(rightExpression, 0)
        if (failed) {
            return(false)
        }
        bool equal = false
        bool less = false
        bool greater = false
        if (decimalNumber(left) and decimalNumber(right)) {
            int64 comparison = compareDecimals(left, right)
            equal = comparison == 0
            less = comparison < 0
            greater = comparison > 0
        } else {
            if (not equality) {
                // Non-numeric relational results are false so forward
                // references in conditions can settle on later passes.
                return(false)
            }
            equal = left.equals(right)
        }
        if (upper.equals("==") or upper.equals("EQ")) {
            return(equal)
        }
        if (upper.equals("!=") or upper.equals("NEQ")) {
            return(not equal)
        }
        if (upper.equals("<") or upper.equals("LT")) {
            return(less)
        }
        if (upper.equals(">") or upper.equals("GT")) {
            return(greater)
        }
        if (upper.equals("<=") or upper.equals("LTE")) {
            return(less or equal)
        }
        return(greater or equal)
    }

    int64 closeBrace(String text, int64 open) {
        int64 depth = 1
        int64 index = open + 1
        int64 quote = 0
        bool escaped = false
        while (index < text.length) {
            int64 current = byte(text, index)
            int64 next = byte(text, index + 1)
            if (quote != 0) {
                if (escaped) {
                    escaped = false
                } else {
                    if (current == 92) {
                        escaped = true
                    } else {
                        if (current == quote) {
                            quote = 0
                        }
                    }
                }
            } else {
                if (current == 34 or current == 39) {
                    quote = current
                } else {
                    if (current == 47 and next == 47) {
                        index = index + 2
                        while (index < text.length and byte(text, index) != 10) {
                            index = index + 1
                        }
                        continue
                    } else {
                        if (current == 47 and next == 42) {
                            index = index + 2
                            while (index + 1 < text.length and not (byte(text, index) == 42 and byte(text, index + 1) == 47)) {
                                index = index + 1
                            }
                            index = index + 1
                        } else {
                            if (current == 123) {
                                depth = depth + 1
                            } else {
                                if (current == 125) {
                                    depth = depth - 1
                                    if (depth == 0) {
                                        return(index)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            index = index + 1
        }
        return(-1)
    }

    int64 closeParen(String text, int64 open) {
        int64 depth = 1
        int64 index = open + 1
        int64 quote = 0
        bool escaped = false
        while (index < text.length) {
            int64 current = byte(text, index)
            if (quote != 0) {
                if (escaped) {
                    escaped = false
                } else {
                    if (current == 92) {
                        escaped = true
                    } else {
                        if (current == quote) {
                            quote = 0
                        }
                    }
                }
            } else {
                if (current == 34 or current == 39) {
                    quote = current
                } else {
                    if (current == 40) {
                        depth = depth + 1
                    } else {
                        if (current == 41) {
                            depth = depth - 1
                            if (depth == 0) {
                                return(index)
                            }
                        }
                    }
                }
            }
            index = index + 1
        }
        return(-1)
    }

    void addDefinition(String name, String body, String file, int64 line, int64 column,
                       list parameters, bool functionLike) {
        if (not validName(name)) {
            report(1000, file, line, 1,
                   format("invalid macro name '{}'", name))
            return
        }
        int64 parameterIndex = 0
        while (parameterIndex < parameters.length) {
            String parameter = parameters[parameterIndex] as String
            if (not validName(parameter)) {
                report(1000, file, line, 1,
                       format("invalid parameter name '{}' in macro '{}'",
                              parameter, name))
                return
            }
            int64 previousIndex = 0
            while (previousIndex < parameterIndex) {
                String previousParameter = parameters[previousIndex] as String
                if (previousParameter.equals(parameter)) {
                    report(1000, file, line, 1,
                           format("duplicate parameter '{}' in macro '{}'",
                                  parameter, name))
                    return
                }
                previousIndex = previousIndex + 1
            }
            parameterIndex = parameterIndex + 1
        }
        Macro existing = findMacro(name)
        if (existing != null) {
            bool sameParameters = existing.parameters.length == parameters.length
            int64 index = 0
            while (index < existing.parameters.length and sameParameters) {
                String oldParameter = existing.parameters[index] as String
                String newParameter = parameters[index] as String
                if (not oldParameter.equals(newParameter)) {
                    sameParameters = false
                }
                index = index + 1
            }
            if (not existing.body.equals(body) or existing.functionLike != functionLike or not sameParameters) {
                report(1001, file, line, 1,
                       format("macro '{}' is already defined", name))
            }
            return
        }
        macros.append(Macro(name, body, file, line, column,
                            parameters, functionLike))
    }

    String processText(String file, String source, int64 firstLine, int64 firstColumn,
                       list parameterNames, list parameterValues, list active,
                       list imports, int64 depth) {
        String output = ""
        if (depth > 128) {
            report(1002, file, firstLine, firstColumn,
                   "macro expansion nesting limit (128) exceeded")
            return(output)
        }
        int64 index = 0
        int64 line = firstLine
        int64 column = firstColumn
        int64 literalQuote = 0
        bool literalEscaped = false
        while (index < source.length and not failed) {
            int64 startIndex = index
            work = work + 1
            totalWork = totalWork + 1
            if (work > 2000000 or totalWork > 20000000) {
                report(2004, file, line, column,
                       "processing work limit (2,000,000 per pass; 20,000,000 total) exceeded")
                break
            }
            int64 current = byte(source, index)
            int64 next = byte(source, index + 1)
            bool handled = false
            if (current == 92 and next == 64) {
                output.append("@")
                index = index + 2
                literalEscaped = false
                handled = true
            }
            if (not handled and literalQuote == 0 and current == 47 and next == 47) {
                int64 end = index
                while (end < source.length and byte(source, end) != 10) {
                    end = end + 1
                }
                if (keepComments) {
                    output.append(byteSpan(source, index, end))
                }
                index = end
                handled = true
            }
            if (not handled and literalQuote == 0 and current == 47 and next == 42) {
                int64 end = index + 2
                while (end + 1 < source.length and not (byte(source, end) == 42 and byte(source, end + 1) == 47)) {
                    end = end + 1
                }
                if (end + 1 >= source.length) {
                    report(1002, file, line, column,
                           "unterminated block comment")
                    break
                }
                if (keepComments) {
                    output.append(byteSpan(source, index, end + 2))
                } else {
                    output.append(" ")
                    String comment = byteSpan(source, index + 2, end)
                    int64 ci = 0
                    while (ci < comment.length) {
                        if (byte(comment, ci) == 10) {
                            output.append("\n")
                        }
                        ci = ci + 1
                    }
                }
                index = end + 2
                handled = true
            }
            if (not handled and literalQuote == 0 and current == 46 and nameStart(next)) {
                int64 wordEnd = nameEnd(source, index + 1)
                String directive = byteSpan(source, index + 1, wordEnd).toLower()
                int64 argumentStart = skipSpace(source, wordEnd)
                if (directive.equals("if")) {
                    if (byte(source, argumentStart) != 40) {
                        report(1007, file, line, column,
                               ".if requires a parenthesized expression")
                        break
                    }
                    int64 expressionEnd = closeParen(source, argumentStart)
                    if (expressionEnd < 0) {
                        report(1007, file, line, column,
                               "unterminated .if expression")
                        break
                    }
                    int64 bodyStart = skipSpace(source, expressionEnd + 1)
                    if (byte(source, bodyStart) != 123) {
                        report(1007, file, line, column,
                               ".if requires a braced body")
                        break
                    }
                    int64 bodyEnd = closeBrace(source, bodyStart)
                    if (bodyEnd < 0) {
                        report(1007, file, line, column,
                               "unterminated .if body")
                        break
                    }
                    conditionFile = file
                    conditionLine = line
                    conditionColumn = column
                    bool selected = evalCondition(
                        byteSpan(source, argumentStart + 1, expressionEnd), 0)
                    String selectedBody = ""
                    int64 selectedLine = lineAfter(source, startIndex,
                                                 bodyStart + 1, line)
                    int64 selectedColumn = columnAfter(source, startIndex,
                                                     bodyStart + 1, column)
                    if (selected) {
                        selectedBody = byteSpan(source, bodyStart + 1, bodyEnd)
                    }
                    index = bodyEnd + 1
                    bool lookingAtElse = true
                    while (lookingAtElse and not failed) {
                        int64 elseStart = skipSpace(source, index)
                        if (byte(source, elseStart) != 46) {
                            lookingAtElse = false
                        } else {
                            int64 elseNameEnd = nameEnd(source, elseStart + 1)
                            String elseName = byteSpan(source, elseStart + 1, elseNameEnd).toLower()
                            if (not elseName.equals("else")) {
                                lookingAtElse = false
                            } else {
                                int64 elseArgs = skipSpace(source, elseNameEnd)
                                bool elseHasExpression = byte(source, elseArgs) == 40
                                bool elseMatches = true
                                if (elseHasExpression) {
                                    int64 elseExpressionEnd = closeParen(source, elseArgs)
                                    if (elseExpressionEnd < 0) {
                                        report(1007, file,
                                            lineAfter(source, startIndex, elseStart, line),
                                            columnAfter(source, startIndex, elseStart, column),
                                            "unterminated .else expression")
                                        break
                                    }
                                    conditionFile = file
                                    conditionLine = lineAfter(
                                        source, startIndex, elseStart, line)
                                    conditionColumn = columnAfter(
                                        source, startIndex, elseStart, column)
                                    elseMatches = evalCondition(
                                        byteSpan(source, elseArgs + 1, elseExpressionEnd), 0)
                                    elseArgs = skipSpace(source, elseExpressionEnd + 1)
                                }
                                if (byte(source, elseArgs) != 123) {
                                    report(1007, file,
                                        lineAfter(source, startIndex, elseStart, line),
                                        columnAfter(source, startIndex, elseStart, column),
                                        ".else requires a braced body")
                                    break
                                }
                                int64 elseBodyEnd = closeBrace(source, elseArgs)
                                if (elseBodyEnd < 0) {
                                    report(1007, file,
                                        lineAfter(source, startIndex, elseStart, line),
                                        columnAfter(source, startIndex, elseStart, column),
                                        "unterminated .else body")
                                    break
                                }
                                if (not selected and (not elseHasExpression or elseMatches)) {
                                    selected = true
                                    selectedBody = byteSpan(source, elseArgs + 1, elseBodyEnd)
                                    selectedLine = lineAfter(
                                        source, startIndex, elseArgs + 1, line)
                                    selectedColumn = columnAfter(
                                        source, startIndex, elseArgs + 1, column)
                                }
                                index = elseBodyEnd + 1
                            }
                        }
                    }
                    if (selected and not failed) {
                        output.append(processText(file, selectedBody, selectedLine,
                            selectedColumn,
                            parameterNames, parameterValues, active, imports, depth + 1))
                    }
                } else {
                if (directive.equals("else")) {
                    report(1008, file, line, column,
                           "misplaced .else directive")
                } else {
                if (directive.equals("define")) {
                    int64 nameStartIndex = argumentStart
                    int64 nameStop = nameEnd(source, nameStartIndex)
                    if (nameStop == nameStartIndex) {
                        report(1000, file, line, column,
                               "expected a macro name after .define")
                        break
                    }
                    String macroName = byteSpan(source, nameStartIndex, nameStop)
                    int64 cursor = skipHorizontal(source, nameStop)
                    list parameters = []
                    bool functionLike = false
                    if (byte(source, cursor) == 40) {
                        functionLike = true
                        int64 close = cursor + 1
                        int64 parenDepth = 1
                        int64 paramStart = close
                        while (close < source.length and parenDepth > 0) {
                            if (byte(source, close) == 40) {
                                parenDepth = parenDepth + 1
                            }
                            if (byte(source, close) == 41 and parenDepth > 0) {
                                parenDepth = parenDepth - 1
                                if (parenDepth == 0) {
                                    String param = byteSpan(source, paramStart, close).trim()
                                    if (param.length > 0 or parameters.length > 0) {
                                        parameters.append(param)
                                    }
                                    break
                                }
                            }
                            if (byte(source, close) == 44 and parenDepth == 1) {
                                parameters.append(byteSpan(source, paramStart, close).trim())
                                paramStart = close + 1
                            }
                            close = close + 1
                        }
                        if (parenDepth != 0) {
                            report(1000, file, line, column,
                                   "unterminated .define parameter list")
                            break
                        }
                        cursor = skipSpace(source, close + 1)
                    } else {
                        cursor = skipHorizontal(source, nameStop)
                    }
                    String body = ""
                    int64 bodyLine = lineAfter(source, startIndex, cursor, line)
                    if (byte(source, cursor) == 123) {
                        int64 closeBody = closeBrace(source, cursor)
                        if (closeBody < 0) {
                            report(1000, file, bodyLine,
                                   columnAfter(source, startIndex, cursor, column),
                                   "unterminated .define body")
                            break
                        }
                        body = byteSpan(source, cursor + 1, closeBody)
                        bodyLine = lineAfter(source, startIndex, cursor + 1, line)
                        index = closeBody + 1
                    } else {
                        if (functionLike) {
                            report(1000, file, line, column,
                                   "a parameterized .define requires a braced body")
                            break
                        } else {
                            index = nameStop
                        }
                    }
                    addDefinition(macroName, body, file, bodyLine,
                                  columnAfter(source, startIndex, cursor + 1, column),
                                  parameters, functionLike)
                } else {
                if (directive.equals("undef")) {
                    int64 nameStop = nameEnd(source, argumentStart)
                    if (nameStop == argumentStart) {
                        report(1000, file, line, column,
                               "expected a macro name after .undef")
                        break
                    }
                    String undefName = byteSpan(source, argumentStart, nameStop)
                    removeDefinition(undefName, file, line, column)
                    index = nameStop
                } else {
                    if (directive.equals("import") or directive.equals("include")) {
                    if (byte(source, argumentStart) != 34) {
                        report(1000, file, line, column,
                               ".import requires a quoted path")
                        break
                    }
                    LiteralValue importPath = parseLiteral(source, argumentStart)
                    if (not importPath.valid) {
                        report(1000, file, line, column,
                               "invalid or unterminated .import path")
                        break
                    }
                    String requested = importPath.value
                    String imported = resolveImport(file, requested)
                    if (imported.length == 0) {
                        report(2005, file, line, column,
                               format("cannot find imported file '{}'", requested))
                        break
                    }
                    output.append(processFile(imported, imports, active, depth + 1))
                    index = importPath.end
                    } else {
                    if (directive.equals("error") or directive.equals("message")) {
                    if (byte(source, argumentStart) != 34) {
                        report(1000, file, line, column,
                               format(".{} requires a quoted message", directive))
                        break
                    }
                    LiteralValue directiveMessage = parseLiteral(source, argumentStart)
                    if (not directiveMessage.valid) {
                        report(1000, file, line, column,
                               "invalid or unterminated directive message")
                        break
                    }
                    String message = directiveMessage.value
                    if (directive.equals("error")) {
                        report(1003, file, line, column, message)
                    } else {
                        io.writeErrorLine(format("{}:{}: message: {}", file, line, message))
                    }
                    index = directiveMessage.end
                    } else {
                        output.append(".")
                        index = index + 1
                    }
                    }
                }
                }
                }
                }
                handled = true
            }
            if (not handled and current == 64 and nameStart(next)) {
                int64 endName = nameEnd(source, index + 1)
                String name = byteSpan(source, index + 1, endName)
                int64 localIndex = findParameter(parameterNames, name)
                if (localIndex >= 0) {
                    String value = parameterValues[localIndex] as String
                    output.append(processText(file, value,
                        line,
                        column, [], [], active,
                        imports, depth + 1))
                    index = endName
                } else {
                    Macro macro = findMacro(name)
                    int64 cursor = skipHorizontal(source, endName)
                    list arguments = []
                    int64 afterReference = endName
                    bool callSyntax = false
                    if (macro != null) {
                        callSyntax = macro.functionLike and macro.parameters.length > 0
                    }
                    if (callSyntax) {
                        if (byte(source, cursor) != 40) {
                            report(1004, file, line, column,
                                   format("macro '{}' requires an argument list", name))
                            break
                        }
                        Arguments parsed = parseArguments(source, cursor)
                        if (not parsed.valid) {
                            report(1004, file, line, column,
                                   format("unterminated argument list for macro '{}'", name))
                            break
                        }
                        arguments = parsed.values
                        afterReference = parsed.end
                        if (arguments.length != macro.parameters.length) {
                            report(1005, file, line, column,
                                   format("macro '{}' expects {} argument(s), got {}",
                                          name, macro.parameters.length, arguments.length))
                            break
                        }
                    }
                    if (macro != null and macro.functionLike and macro.parameters.length == 0 and byte(source, cursor) == 40) {
                        Arguments parsedEmpty = parseArguments(source, cursor)
                        if (not parsedEmpty.valid or parsedEmpty.values.length > 0) {
                            report(1005, file, line, column,
                                   format("macro '{}' takes no arguments", name))
                            break
                        }
                        afterReference = parsedEmpty.end
                    }
                    if (macro == null) {
                        output.append(byteSpan(source, index, endName))
                        index = endName
                    } else {
                        if (inList(active, name)) {
                            report(1006, file, line, column,
                                   format("macro expansion cycle involving '{}'", name))
                            break
                        } else {
                            list nestedActive = []
                            int64 activeIndex = 0
                            while (activeIndex < active.length) {
                                nestedActive.append(active[activeIndex])
                                activeIndex = activeIndex + 1
                            }
                            nestedActive.append(name)
                            list parentTrace = currentTrace
                            list nestedTrace = []
                            int64 traceIndex = 0
                            while (traceIndex < currentTrace.length) {
                                nestedTrace.append(currentTrace[traceIndex])
                                traceIndex = traceIndex + 1
                            }
                            nestedTrace.append(format(
                                "expanded macro @{} at {}:{} (defined at {}:{})",
                                name, file, line,
                                macro.file, macro.line))
                            currentTrace = nestedTrace
                            String expanded = processText(macro.file, macro.body, macro.line,
                                macro.column, macro.parameters, arguments, nestedActive,
                                imports, depth + 1)
                            currentTrace = parentTrace
                            output.append(expanded)
                            index = afterReference
                        }
                    }
                }
                handled = true
            }
            if (not handled) {
                int64 width = utf8Width(current)
                output.append(byteSpan(source, index, index + width))
                if (literalQuote != 0) {
                    if (literalEscaped) {
                        literalEscaped = false
                    } else {
                        if (current == 92) {
                            literalEscaped = true
                        } else {
                            if (current == literalQuote) {
                                literalQuote = 0
                            }
                        }
                    }
                } else {
                    if (current == 34 or current == 39) {
                        literalQuote = current
                    }
                }
                index = index + width
            }
            if (output.length > outputLimit) {
                report(2006, file, line, column,
                       "expanded output exceeds the 7,000,000-byte limit")
                break
            }
            int64 lineCursor = startIndex
            while (lineCursor < index) {
                if (byte(source, lineCursor) == 10) {
                    line = line + 1
                    column = 1
                } else {
                    int64 currentByte = byte(source, lineCursor)
                    if (currentByte < 128 or currentByte >= 192) {
                        column = column + 1
                    }
                }
                lineCursor = lineCursor + 1
            }
        }
        if (literalQuote != 0 and not failed) {
            report(1002, file, line, column,
                   "unterminated quoted literal")
        }
        return(output)
    }

    String process(String input) {
        String previous = ""
        String result = ""
        int64 pass = 0
        while (pass < 256 and not failed) {
            work = 0
            int64 definitionsBeforePass = definitionCount()
            list imports = []
            list active = []
            result = processFile(input, imports, active, 0)
            bool definitionsStable = definitionCount() == definitionsBeforePass
            if (failed or (pass > 0 and definitionsStable and result.equals(previous))) {
                return(result)
            }
            previous = result
            pass = pass + 1
        }
        if (not failed) {
            report(2007, input, 1, 1,
                   "processing did not converge within 256 passes")
        }
        return(result)
    }

    bool writeOutput(String path, String text) {
        if (path.length == 0) {
            io.write(text)
            io.flush()
            return(true)
        }
        Sys.FileSystem fs = Sys.FileSystem()
        String temporary = format("{}.cmacros.tmp", path)
        if (fs.exists(temporary)) {
            report(2008, path, 1, 1,
                   format("temporary output path already exists: '{}'", temporary))
            return(false)
        }
        try {
            Sys.File output = Sys.File(temporary, "wb")
            int64 written = output.write(text)
            output.close()
            if (written != text.length) {
                report(2009, path, 1, 1, "failed to write complete output")
                fs.remove(temporary)
                return(false)
            }
            if (not fs.rename(temporary, path)) {
                report(2009, path, 1, 1,
                       format("cannot replace output file: {}", Sys.System().lastError()))
                fs.remove(temporary)
                return(false)
            }
        } except() as message {
            report(2009, path, 1, 1, format("cannot write output: {}", message))
            fs.remove(temporary)
            return(false)
        }
        return(true)
    }

    void printHelp() {
        io.writeLine("cmacros: v1.0")
        io.writeLine("Cwhip macro processor")
        io.writeLine("")
        io.writeLine("Usage: cmacros [options] [input]")
        io.writeLine("")
        io.writeLine("  input        Source file, or - for stdin (default: stdin)")
        io.writeLine("  -I DIR       Add a directory to the import search path")
        io.writeLine("  -D NAME[=V]  Define a command-line macro")
        io.writeLine("  -o FILE      Write output to FILE, or - for stdout (default: stdout)")
        io.writeLine("  -k           Keep // and /* */ comments in the output")
        io.writeLine("  -v N         Set verbosity (accepted for compatibility)")
        io.writeLine("  -h, --help   Show this help")
        io.writeLine("  -V, --version Show the version")
    }

    int64 byteSpanBound(int64 value, int64 length) {
        int64 index = value
        if (index < 0) { index = index + length }
        if (index < 0) { return(0) }
        if (index > length) { return(length) }
        return(index)
    }
    String byteSpan(String text, int64 first, int64 last) {
        int64 lower = byteSpanBound(first, text.length)
        int64 end = byteSpanBound(last, text.length)
        if (end <= lower) { return("") }
        return(text[lower..(end - 1)])
    }
}

class ByteSpan {
    int64 byteSpanBound(int64 value, int64 length) {
        int64 index = value
        if (index < 0) { index = index + length }
        if (index < 0) { return(0) }
        if (index > length) { return(length) }
        return(index)
    }
    String byteSpan(String text, int64 first, int64 last) {
        int64 lower = byteSpanBound(first, text.length)
        int64 end = byteSpanBound(last, text.length)
        if (end <= lower) { return("") }
        return(text[lower..(end - 1)])
    }
}

start {
    Sys.Process process = Sys.Process()
    Sys.StandardIO io = Sys.System().io()
    Cli.CommandLine commandLine = Cli.CommandLine("cmacros", "Cwhip macro processor", "1.0")
    Cli.Option help = Cli.Option()
    help.shortName = "h"
    help.longName = "help"
    help.name = "help"
    help.action = Cli.Action().HELP
    commandLine.addOption(help)
    Cli.Option version = Cli.Option()
    version.shortName = "V"
    version.longName = "version"
    version.name = "version"
    version.action = Cli.Action().VERSION
    commandLine.addOption(version)
    Cli.Option output = Cli.Option()
    output.shortName = "o"
    output.longName = "ofile"
    output.name = "output"
    output.description = "write output to FILE"
    output.valueType = Cli.ValueType().STRING
    commandLine.addOption(output)
    Cli.Option includePath = Cli.Option()
    includePath.shortName = "I"
    includePath.longName = "include"
    includePath.name = "include"
    includePath.description = "import search directory"
    includePath.valueType = Cli.ValueType().STRING
    includePath.isList = true
    commandLine.addOption(includePath)
    Cli.Option define = Cli.Option()
    define.shortName = "D"
    define.longName = "define"
    define.name = "define"
    define.description = "define a command-line macro"
    define.valueType = Cli.ValueType().STRING
    define.isList = true
    // Keep each -D argument intact so NAME=value stays one definition.
    define.listSeparator = "\n"
    commandLine.addOption(define)
    Cli.Option keepComments = Cli.Option()
    keepComments.shortName = "k"
    keepComments.longName = "keep-comments"
    keepComments.name = "keep-comments"
    keepComments.description = "keep // and /* */ comments in the output"
    keepComments.valueType = Cli.ValueType().FLAG
    commandLine.addOption(keepComments)
    Cli.Option verbosity = Cli.Option()
    verbosity.shortName = "v"
    verbosity.longName = "verbosity"
    verbosity.name = "verbosity"
    verbosity.description = "verbosity (accepted for compatibility)"
    verbosity.valueType = Cli.ValueType().NUMBER
    commandLine.addOption(verbosity)
    Cli.Positional inputPos = Cli.Positional()
    inputPos.name = "input"
    inputPos.description = "source file, or - for stdin (default: stdin)"
    inputPos.required = false
    commandLine.addPositional(inputPos)

    String problem = ""
    try {
        commandLine.parseArgv()
    } except() as error {
        problem = format("{}", error)
        if (problem.startsWith("unknown option: ")) {
            problem = format("unknown option '{}'", problem[16..problem.length - 1])
        }
        if (problem.startsWith("option --ofile requires")) {
            problem = "option --ofile requires a file name"
        }
        if (problem.startsWith("option -o requires")) {
            problem = "option -o requires a file name"
        }
        if (problem.startsWith("option --include requires") or problem.startsWith("option -I requires")) {
            problem = "option -I requires a directory"
        }
        if (problem.startsWith("option --define requires") or problem.startsWith("option -D requires")) {
            problem = "option -D requires a definition"
        }
        if (problem.startsWith("option --verbosity requires") or problem.startsWith("option -v requires")) {
            problem = "option -v requires a non-negative number"
        }
        if (problem.startsWith("unexpected positional")) {
            problem = "only one input file may be specified"
        }
    }
    if (commandLine.currentAction() == Cli.Action().HELP) {
        Processor([]).printHelp()
        process.exit(0)
    }
    if (commandLine.currentAction() == Cli.Action().VERSION) {
        io.writeLine("cmacros: v1.0")
        process.exit(0)
    }
    if (problem.length > 0 or commandLine.allPositionalValues().length > 1) {
        if (problem.length == 0) {
            problem = "only one input file may be specified"
        }
        io.writeErrorLine(format("cmacros: error[CMACRO0001]: {}", problem))
        io.writeErrorLine("Try 'cmacros --help' for usage.")
        process.exit(2)
    }
    String input = ""
    if (commandLine.allPositionalValues().length == 1) {
        input = commandLine.allPositionalValues()[0] as String
    }
    String outputPath = ""
    if (commandLine.wasProvided("output")) {
        outputPath = commandLine.value("output")
    }
    if (outputPath.equals("-")) {
        outputPath = ""
    }
    bool fromStdin = input.length == 0 or input.equals("-")
    list paths = commandLine.valuesFor("include")
    list definitions = commandLine.valuesFor("define")
    String macroPath = process.getEnv("MACRO_PATH")
    if (macroPath.length > 0) {
        list environmentPaths = macroPath.split(":")
        int64 item = 0
        while (item < environmentPaths.length) {
            paths.append(environmentPaths[item] as String)
            item = item + 1
        }
    }
    Processor processor = Processor(paths)
    processor.keepComments = commandLine.switchValue("keep-comments")
    if (fromStdin) {
        String content = ""
        String chunk = io.read(65536)
        while (chunk.length > 0) {
            content.append(chunk)
            if (content.length > 16777216) {
                io.writeErrorLine("cmacros: error[CMACRO2001]: input exceeds the 16 MiB source limit")
                process.exit(1)
            }
            chunk = io.read(65536)
        }
        input = "<stdin>"
        processor.cacheSource(input, content)
    } else {
        String absoluteInput = Sys.FileSystem().absolutePath(input)
        if (absoluteInput.length == 0 and Sys.FileSystem().isFile(format("{}.txt", input))) {
            input = format("{}.txt", input)
        }
        if (absoluteInput.length > 0) {
            input = absoluteInput
        }
        if (not Sys.FileSystem().isFile(input)) {
            io.writeErrorLine(format("cmacros: error[CMACRO2000]: cannot open input '{}'", input))
            process.exit(1)
        }
    }
    int64 definitionIndex = 0
    while (definitionIndex < definitions.length) {
        String definition = definitions[definitionIndex] as String
        int64 equals = definition.find("=")
        String name = definition
        String body = ""
        if (equals >= 0) {
            name = ByteSpan().byteSpan(definition, 0, equals)
            body = ByteSpan().byteSpan(definition, equals + 1, definition.length)
        }
        list noParameters = []
        processor.addDefinition(name, body, "<command line>", 1, 1, noParameters, true)
        definitionIndex = definitionIndex + 1
    }
    String result = processor.process(input)
    if (not processor.failed) {
        processor.writeOutput(outputPath, result)
    }
    if (processor.failed) {
        process.exit(1)
    }
}
