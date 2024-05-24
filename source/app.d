import colored : red, white;
import core.time : Duration, msecs;
import photon : channel, Channel, go, runFibers, select, startloop;
import std.algorithm : map;
import std.conv : to;
import std.datetime.systime : Clock, SysTime;
import std.process : pipeProcess;
import std.range : array, join, take;
import std.stdio : write, stderr, stdin, stdout, writeln;
import std.string : format, leftJustify, rightJustify, strip;
import unit : Unit;

static immutable TIME = Unit("time", [
                               Unit.Scale("", 1, 3), Unit.Scale(".", 1000, 2), Unit.Scale(":", 60, 4),
                             ]);

auto formatPart(Unit.Part part)
{
    return format!("%s%s")(part.value.to!string.rightJustify(part.digits, '0'), part.name);
}

string formatLine(string line, bool isStdout, SysTime time, Duration totalDelta, Duration lineDelta)
{
    auto tD = TIME.transform(totalDelta.total!("msecs")).map!(i => i.formatPart).join("");
    auto lD = TIME.transform(lineDelta.total!("msecs")).map!(i => i.formatPart).join("");
    return format!("%s|%s|%s: %s")(time.toISOExtString().leftJustify(26, '0'), tD, lD, isStdout ? line:line.red.to!string);
}

struct StdoutLine
{
    string line;
}

struct StderrLine
{
    string line;
}

struct Done
{
}

void copyLines(From, T)(From from, shared(Channel!(T)) to, Channel!Done done)
{
    foreach (line; from.byLineCopy())
    {
        to.put(T(line));
    }
    to.close();
    done.put(Done());
}

class State {
public:
    immutable(SysTime) timeOfStart;
    string line = "";
    bool isStdout = true;
    SysTime timeOfLine;
    uint done = 0;
    this()
    {
        timeOfStart = Clock.currTime();
        timeOfLine = Clock.currTime();
    }

    Duration durationOfLine(SysTime now) {
        return now - timeOfLine;
    }
    Duration totalDuration(SysTime now) {
        return now - timeOfStart;
    }
    // add a new line to the output
    void newLine(string line, bool isStdout) {
        renderFinishedLine();
        this.line = line;
        this.isStdout = isStdout;
        this.timeOfLine = Clock.currTime();
        renderCurrentLine();
    }
    // refresh the current line
    void refreshLine()
    {
        renderCurrentLine();
    }
    // called when stdout or stderr is done
    void streamDone() {
        done++;
    }
    // checks if more events need to be processed
    bool finished() {
        return done >= 2;
    }
    // finishes the output
    void finish() {
        renderFinishedLine();
    }
    private void renderFinishedLine()
    {
        auto now = Clock.currTime();
        writeln(line.formatLine(isStdout, timeOfLine, timeOfLine - timeOfStart, durationOfLine(now)));
    }
    private void renderCurrentLine() {
        auto now = Clock.currTime();
        write(line.formatLine(isStdout, now, totalDuration(now), durationOfLine(now)));
        write("\r");
    }
}

int main(string[] args)
{
    startloop(); // start the event loop thread and initializes Photon's data structures

    if (args.length > 1 && args[1] == "test")
    {
        test();
        return 0;
    }

    auto pipes = pipeProcess(args[1 .. $]);
    auto stdoutChannel = channel!StdoutLine(100);
    auto stderrChannel = channel!StderrLine(100);
    auto doneChannel = channel!Done(2);
    auto refreshChannel = channel!bool(100);
    auto state = new State();

    go({
            while (!state.finished())
            {
                // dfmt off
                select(
                  // cast to void delegate, because otherwise this is a nothrow delegate, that does not mix well with the other throw delegates!
                  doneChannel, cast(void delegate()) { doneChannel.take(1).front; state.streamDone(); },
                  stdoutChannel, { state.newLine(stdoutChannel.take(1).front.line, isStdout: true); },
                  stderrChannel, { state.newLine(stderrChannel.take(1).front.line, isStdout: false); },
                  refreshChannel, {
                      refreshChannel.take(1).front;
                      state.refreshLine();
                  },
                );
                // dfmt on
                stdout.flush();
            }
            state.finish();
        });

    go({ copyLines(pipes.stdout, stdoutChannel, doneChannel); });
    go({ copyLines(pipes.stderr, stderrChannel, doneChannel); });
    go({
            while (!state.finished())
            {
                import core.thread.osthread : Thread;

                Thread.sleep(100.msecs);
                refreshChannel.put(true);
            }
        });
    runFibers();

    return 0;
}

void test()
{
    import core.thread.osthread : Thread;
    import core.time : seconds;
    for (int i = 1; i < 6; ++i)
    {
        Thread.sleep(2.seconds);
        writeln(i);
        stdout.flush();
        if (i % 2 == 0)
        {
            stderr.writeln(i);
            stderr.flush();
        }
        Thread.sleep(2.seconds);
    }
}
