import core.time : Duration, msecs, seconds;
import core.thread.osthread : Thread;
import std.algorithm : map;
import std.concurrency : OwnerTerminated, LinkTerminated, receive, ownerTid,
    receiveTimeout, send, spawnLinked, Tid;
import std.conv : to;
import std.datetime.systime : Clock, SysTime;
import std.range : array, join;
import std.stdio : stderr, stdin, stdout, write, writeln, File;
import std.string : format, leftJustify, rightJustify, strip;
import unit : Unit;
import std.process : pipeProcess;
import colored : red;

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
    return format!("%s|%s|%s: %s")(time.toISOExtString().leftJustify(27, '0'), tD, lD, isStdout ? line:line.red.to!string);
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

struct Tick
{
}

void lineUpdater()
{

    version (OSX) {
        import core.sys.darwin.pthread : pthread_setname_np;
        import std.string : toStringz;
        pthread_setname_np("ticker".toStringz());
    }
    // dfmt off
    try
    {
        while (true)
        {
            // dfmt off
            receiveTimeout(1000.msecs, (Tick _) {});
            // dfmt on
            ownerTid.send(Tick());
        }
    }
    catch (OwnerTerminated _)
    {
    }
    // dfmt on
}

struct DataForStdout
{
    string line;
}

struct DataForStderr
{
    string line;
}

void read(T)(shared(File delegate()) get, string theName)
{
    Thread.getThis().name(theName);
    auto f = get();
    foreach (line; f.byLineCopy())
    {
        ownerTid.send(T(line.idup));
    }
}

int main(string[] args)
{

    if (args.length > 1 && args[1] == "test")
    {
        test();
        return 0;
    }
    Thread.getThis().name("main");
    auto state = new State();
    auto updater = spawnLinked(&lineUpdater);

    auto pipes = pipeProcess(args[1 .. $]);
    auto getStdout() => pipes.stdout; // strange workaround as more direct ways do not work for me
    auto getStderr() => pipes.stderr;
    spawnLinked(&read!(DataForStdout), cast(shared)&getStdout, "stdoutReader");
    spawnLinked(&read!(DataForStderr), cast(shared)&getStderr, "stderrReader");

    while (!state.finished())
    {
        receive(
          (DataForStdout data)
          {
              state.newLine(data.line, true);
          },
          (DataForStderr data) {
              state.newLine(data.line, false);
          },
          (Tick _)
          {
              state.refreshLine();
          },
          (LinkTerminated _) {
              state.streamDone();
          }
        );
        stdout.flush();
    }
    state.finish();
    return 0;
}

void test()
{
    import core.thread.osthread : Thread;
    import core.time : seconds;
    for (int i = 1; i < 60; ++i)
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
