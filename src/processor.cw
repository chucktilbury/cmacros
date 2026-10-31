// Macro processor core.
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

    bool isDefinednessOperand(String expression)
    bool isAtOperand(String expression)
    void conditionError(String message)
    bool wordBoundary(String text, int64 index)
    int64 operatorPriority(String operator)
    String operatorAt(String text, int64 index)
    Operator findOperator(String expression, int64 wantedPriority)
    bool wrapsWholeExpression(String expression)
    bool decimalNumber(String value)
    bool decimalZero(String value)
    int64 compareDecimals(String left, String right)
    bool valueTruth(String value)
    bool evalCondition(String expression, int64 recursion)
    bool atReferenceDefinedNonempty(String expression, int64 recursion)
    String resolveConditionValue(String expression, int64 recursion)
    bool compareCondition(String leftExpression, String rightExpression, String operator)
    void cacheSource(String path, String content)
    String readFile(String path, int64 line)
    String process(String input)
    bool writeOutput(String path, String text)
    void printHelp()

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
