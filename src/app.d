import std.stdio;
import std.format;
import std.algorithm;
import std.range;
import std.getopt;
import std.file: exists, isFile, append;
import std.path;
import std.process;
import std.ascii;
import std.conv;

import term;

enum CritExt = ".crit";

void parseKV(const(char)[] line, ref Comment comment) {
    uint index;
    char i_char = line[index];
    while (i_char != '=') {
        if (i_char == '\n') {
            return;
        }
        index++;
        i_char = line[index];
    }
    const key = line[0..index-1].strip!(isWhite);
    const val = line[index+1..$-1].strip!(isWhite);
    switch(key) {
        case ("email"):
            comment.email = val.to!string;
            break;
        case ("author"):
            comment.author = val.to!string;
            break;
        case ("message"):
            comment.message = val.to!(string[]);
            break;
        case ("begin"):
            comment.line_begin = val.to!uint;
            break;
        case ("end"):
            comment.line_end = val.to!uint;
            break;
        default:
            throw new Exception(format("Unkown key %s", key));
    }
}

// A very bad not good crit file parser
struct CritParser {
    string file_name;
    File crit_file;

    char[] line;
    bool _empty;

    this(string file_name) {
        this.file_name = file_name;
        crit_file = File(file_name);

        crit_file.readln(line);
        if(line.length == 0) {
            _empty = true;
        }
    }

    ~this() {
        crit_file.close;
    }

    Comment front() {
        Comment comment;

        while(line.length != 0 && line[0] != '[') {
            crit_file.readln(line);
        }

        while(line.length != 0 && !line[0].isWhite) {
            if(line[0] != '\n') {
                line.parseKV(comment);
            }
            crit_file.readln(line);
        }
        
        if(line.length == 0) {
            _empty = true;
        }

        return comment;
    }

    void popFront() {
        crit_file.readln(line);
        if(line.length == 0) {
            _empty = true;
        }
    }

    bool empty() {
        return _empty;
    }

}
static assert(isInputRange!CritParser);


struct Git {
    enum git_cmd = "git";
    string name() {
        auto result = execute([git_cmd, "config", "user.name"]);
        if(result.status != 0) {
            throw new Exception(result.output);
        }
        return result.output.stripRight('\n');
    }
    string email() {
        auto result = execute([git_cmd, "config", "user.email"]);
        if(result.status != 0) {
            throw new Exception(result.output);
        }
        return result.output.stripRight('\n');
    }
}

static Git git;

struct Comment {
    string author;
    string email;
    string[] message;
    uint line_begin;
    uint line_end;
    Comment* parent;

    enum GREENBAR = CYAN~"   | "~RESET;

    string toString() const {
        auto output = 
            format(GREENBAR~Mode.Bold.code~"%s"~Mode.None.code~" <%s> (%s,%s)\n", author, email, line_begin, line_end) 
            ~ GREENBAR~"\n"
            ~ format("%("~GREENBAR~"%s\n%)", message);

        return output;
    }
}

void printFileWithComments(File file, Comment[] comments) { 
    const num_width = 4;
    foreach(line_num, line; file.byLine.enumerate(1)) {
        string padded_linenum = line_num.to!string.padLeft(' ', num_width).to!string;
        bool isCommented = comments.any!((c) => line_num >= c.line_begin
         && line_num <= c.line_end);

        if (!isCommented) {
            writefln("%s %s", padded_linenum, line);
        }
        else {
            writefln(CYAN~"%s "~RESET~"%s", padded_linenum , line);
            foreach(c; comments) {
                if (line_num == c.line_end) {
                    writeln(Comment.GREENBAR);
                    writeln(c);
                    writeln(Comment.GREENBAR);
                }
            }
        }
    }
}

void addComment(string file_name, Comment comment) {
    string crit_file_name = file_name ~ CritExt;
    auto output = "[comment]\n" 
        ~ format("author = %s\n", comment.author)
        ~ format("email = %s\n", comment.email)
        ~ format("message = %s\n", comment.message)
        ~ format("begin = %s\n", comment.line_begin)
        ~ format("end = %s\n\n", comment.line_end);

    auto crit_file = File(crit_file_name, "a");
    crit_file.write(output);
}

void showComments(string file_name) {
    string crit_file_name = file_name ~ CritExt;
    auto comments = CritParser(crit_file_name);
    // foreach(c; comments) {
    //     c.writeln;
    // }
    File(file_name).printFileWithComments(comments.array);
}


int main(string[] args)
{
    uint[] lines;
    string message;

    arraySep = ",";
    auto main_args = getopt(
            args,
            "l|lines", "line begin,end", &lines,
            "m|message", "The message which the comment should contain", &message,
    );

    if(args.length < 3) {
        stderr.writeln("No file");
        return 1;
    }
    string file_name = args[2];
    if(!file_name.exists) {
        stderr.writefln("%s doesn't exist", file_name);
        return 1;
    }
    if(!file_name.isFile) {
        stderr.writefln("%s is not a regular file", file_name);
        return 1;
    }

    if(args.length < 2) {
        stderr.writeln("No command specified");
        return 1;
    }

    string cmd = args[1];
    switch(cmd) {
        case "add":
            auto comment = Comment(git.name, git.email, [message], lines[0], lines[1]);

            file_name.addComment(comment);
            break;
        case "show":
            file_name.showComments;
            break;
        default:
            stderr.writefln("Invalid command %s", args[1]);
            break;
    }

    return 0;
}

unittest {
    auto comment = Comment("Jens", "jens@example.com", 
            ["This is some greate code",
             "I Really like it"
            ],
            12,
            13,
            );

    printFileWithComments(File(__FILE__), comment);
}
