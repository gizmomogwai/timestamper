import core.time : Duration, msecs;
import std.algorithm : map;
import std.concurrency : OwnerTerminated, LinkTerminated, receive,
    receiveTimeout, send, spawnLinked, Tid;
import std.conv : to;
import std.datetime.systime : Clock, SysTime;
import std.range : array, join;
import std.stdio : stdin, stdout, write, writeln;
import std.string : format, leftJustify, rightJustify, strip;
import unit : Unit;

struct Tick
{
}

static immutable TIME = Unit("time", [
    Unit.Scale("ms", 1, 3), Unit.Scale("s", 1000, 2), Unit.Scale("m", 60, 4),
]);

auto formatPart(Unit.Part part)
{
    return format!("%s%s")(part.value.to!string.rightJustify(part.digits, ' '), part.name);
}

string formatLine(SysTime start, Duration totalDelta, Duration lineDelta, string line)
{
    auto tD = TIME.transform(totalDelta.total!("msecs")).map!(i => i.formatPart()).join(" ");
    auto lD = TIME.transform(lineDelta.total!("msecs")).map!(i => i.formatPart()).join(" ");
    return format!("%s, %s, %s: %s")(start.toISOString().leftJustify(22, '0'), tD, lD, line);
}

void printer()
{
    try
    {
        auto timeOfStart = Clock.currTime();
        string lastLine = "";
        auto timeOfLastLine = timeOfStart;
        auto now = Clock.currTime;
        auto totalDelta = now - timeOfStart;
        auto lineDelta = now - timeOfLastLine;
        while (true)
        {
            receive((string line) {
                now = Clock.currTime();
                totalDelta = now - timeOfStart;
                lineDelta = now - timeOfLastLine;
                writeln("\r", formatLine(now, totalDelta, lineDelta, lastLine));
                lastLine = line.strip;
                timeOfLastLine = now;
            }, (Tick _) { now = Clock.currTime; write("\r"); },);
            totalDelta = now - timeOfStart;
            lineDelta = now - timeOfLastLine;
            write(formatLine(now, totalDelta, lineDelta, lastLine));
            stdout.flush();
        }
    }
    catch (OwnerTerminated _)
    {
    }
}

void lineUpdater(Tid printer)
{
    bool done = false;
    while (!done)
    {
        receiveTimeout(1000.msecs, (OwnerTerminated _) { done = true; },);
        if (!done)
        {
            printer.send(Tick());
        }
    }
}

int main(string[] args)
{
    if (args.length > 1 && args[1] == "test")
    {
        import core.thread.osthread : Thread;

        writeln(1);
        Thread.sleep(2000.msecs);
        writeln(2);
        Thread.sleep(2000.msecs);
        writeln(3);
        Thread.sleep(2000.msecs);
        return 0;
    }
    auto printerThread = spawnLinked(&printer);
    auto updater = spawnLinked(&lineUpdater, printerThread);

    foreach (line; stdin.byLineCopy())
    {
        printerThread.send(line);
    }
    return 0;
}
