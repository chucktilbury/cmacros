import system as Sys
import cli as Cli

include "types.cw"
include "processor.cw"
include "conditions.cw"
include "io.cw"

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
