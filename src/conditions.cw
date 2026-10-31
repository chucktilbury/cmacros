// Conditional expression evaluation for Processor.
bool Processor.isDefinednessOperand(String expression) {
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

bool Processor.isAtOperand(String expression) {
        return(expression.trim().startsWith("@"))
    }

void Processor.conditionError(String message) {
        report(1009, conditionFile, conditionLine, conditionColumn, message)
    }

bool Processor.wordBoundary(String text, int64 index) {
        if (index < 0 or index >= text.length) {
            return(true)
        }
        int64 value = byte(text, index)
        return(space(value) or value == 40 or value == 41)
    }

int64 Processor.operatorPriority(String operator) {
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

String Processor.operatorAt(String text, int64 index) {
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

Operator Processor.findOperator(String expression, int64 wantedPriority) {
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

bool Processor.wrapsWholeExpression(String expression) {
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

bool Processor.decimalNumber(String value) {
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

bool Processor.decimalZero(String value) {
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

int64 Processor.compareDecimals(String left, String right) {
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

bool Processor.valueTruth(String value) {
        String trimmed = value.trim()
        if (trimmed.length == 0) {
            return(false)
        }
        if (decimalNumber(trimmed)) {
            return(not decimalZero(trimmed))
        }
        return(true)
    }

bool Processor.evalCondition(String expression, int64 recursion) {
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

bool Processor.atReferenceDefinedNonempty(String expression, int64 recursion) {
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

String Processor.resolveConditionValue(String expression, int64 recursion) {
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

bool Processor.compareCondition(String leftExpression, String rightExpression, String operator) {
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

