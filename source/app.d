import core.time : Duration, msecs;
import std.algorithm : map;
import std.concurrency : LinkTerminated, receive, receiveTimeout, send, spawnLinked, Tid;
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

string formatLine(SysTime start, Duration delta, string line)
{
    auto h = TIME.transform(delta.total!("msecs")).map!(i => i.formatPart()).join(" ");
    return format!("%s, %s: %s")(start.toISOString().leftJustify(22, '0'), h, line);
}

void printer()
{
    auto startTime = Clock.currTime();
    bool done = false;
    string lastLine = "";
    auto now = Clock.currTime;
    auto delta = now - startTime;
    while (!done)
    {
        receive((string line) {
            now = Clock.currTime();
            delta = now - startTime;
            writeln("\r", formatLine(now, delta, lastLine));
            lastLine = line.strip;
        }, (Tick _) { now = Clock.currTime; write("\r"); }, (LinkTerminated _) {
            done = true;
        },);
        delta = now - startTime;
        write(formatLine(now, delta, lastLine));
        stdout.flush();
    }
}

void lineUpdater(Tid printer)
{
    bool done = false;
    while (!done)
    {
        receiveTimeout(1000.msecs, (LinkTerminated _) { done = true; },);
        printer.send(Tick());
    }
}

int main(string[] args)
{
    auto printerThread = spawnLinked(&printer);
    auto updater = spawnLinked(&lineUpdater, printerThread);

    foreach (line; stdin.byLineCopy())
    {
        printerThread.send(line);
    }
    return 0;
}
