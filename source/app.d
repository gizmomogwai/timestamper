import core.time : Duration, msecs, seconds;
import std.algorithm : map;
import std.concurrency : OwnerTerminated, LinkTerminated, receive,
    receiveTimeout, send, spawnLinked, Tid;
import std.conv : to;
import std.datetime.systime : Clock, SysTime;
import std.range : array, join;
import std.stdio : stdin, stdout, write, writeln;
import std.string : format, leftJustify, rightJustify, strip;
import unit : Unit;

static immutable TIME = Unit("time", [
    Unit.Scale("", 1, 3), Unit.Scale(".", 1000, 2), Unit.Scale(":", 60, 4),
]);

auto formatPart(Unit.Part part)
{
    return format!("%s%s")(part.value.to!string.rightJustify(part.digits, '0'), part.name);
}

string formatLine(SysTime start, Duration totalDelta, Duration lineDelta, string line)
{
    auto tD = TIME.transform(totalDelta.total!("msecs")).map!(i => i.formatPart).join("");
    auto lD = TIME.transform(lineDelta.total!("msecs")).map!(i => i.formatPart).join("");
    return format!("%s|%s|%s: %s")(start.toISOExtString().leftJustify(26, '0'), tD, lD, line);
}

struct Tick
{
}

void printer()
{
    // dfmt off
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
            receive(
                (string line)
                {
                    now = Clock.currTime();
                    totalDelta = now - timeOfStart;
                    lineDelta = now - timeOfLastLine;
                    writeln("\r", formatLine(now, totalDelta, lineDelta, lastLine));
                    lastLine = line.strip;
                    timeOfLastLine = now;
                },
                (Tick _)
                {
                    now = Clock.currTime; write("\r");
                },
            );
            totalDelta = now - timeOfStart;
            lineDelta = now - timeOfLastLine;
            write(formatLine(now, totalDelta, lineDelta, lastLine));
            stdout.flush();
        }
    }
    catch (OwnerTerminated _)
    {
    }
    // dfmt on
}

void lineUpdater(Tid printer)
{
    // dfmt off
    try
    {
        while (true)
        {
            receiveTimeout(
              1000.msecs,
              (Tick _)
              {
              },
            );
            printer.send(Tick());
        }
    }
    catch (OwnerTerminated _)
    {
    }
    // dfmt on
}

int main(string[] args)
{
    if (args.length > 1 && args[1] == "test")
    {
        import core.thread.osthread : Thread;

        for (int i = 1; i < 6; ++i)
        {
            writeln(i);
            stdout.flush();
            Thread.sleep(2.seconds);
        }
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
