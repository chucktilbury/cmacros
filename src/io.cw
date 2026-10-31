// Source/output I/O helpers for Processor.
void Processor.cacheSource(String path, String content) {
        cachedPaths.append(path)
        cachedContents.append(content)
    }

String Processor.readFile(String path, int64 line) {
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

String Processor.process(String input) {
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

bool Processor.writeOutput(String path, String text) {
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

void Processor.printHelp() {
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

