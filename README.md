# warden

A SPARK proxy that stands between an operator and an industrial controller,
and only lets through the Modbus/TCP requests it can vouch for.

Everything runs on your laptop: the proxy, a simulated pumping station, an
operator and an adversary. No hardware, synthetic data only.

This repository is a **seed**. It works, it has a shape, and it is deliberately
gullible: today it forwards almost anything. Your project is to make it refuse
everything it should refuse, without ever breaking the operator's traffic, and
to prove part of that.

```
 operator                                       pumping station
 workstation  ---->  [ warden ]  ---->  controller: tank, pump, valve
                         ^
 adversary  -------------+
```

Modbus has no passwords and no permissions: a controller obeys whoever can
reach it. The proxy is the only thing between the network and the pump.

## Install

You need two things:

- [Alire](https://alire.ada.dev), the Ada package manager
- Python 3 (on Windows, type `python` where this page says `python3`)

Then build once, from the root of the repository. The first build downloads
the compiler.

```console
alr build
```

## Run it

Open three terminals at the root of the repository.

Terminal 1, the pumping station:

```console
python3 tools/plant.py
```

Terminal 2, the proxy:

```console
alr run
```

Terminal 3, the operator:

```console
python3 tools/workstation.py
```

The operator reads the tank level once per second and keeps it between 40 %
and 60 % by starting and stopping the pump. Each terminal prints what it sees:

```
plant: level  41.0%  pump OFF  valve OPEN    trip 90.0%
warden: request of 12 bytes, verdict=ACCEPTED
operator: level  39.5%  pump OFF  -> pump ON
```

Stop any of them with Ctrl+C.

## Attack it

With the three terminals still running, open a fourth one:

```console
python3 tools/attack.py sabotage
```

Watch terminal 1 for thirty seconds. The attacker closed the valve, started
the pump, disabled the safety trip and froze the controller, all through the
proxy, and the proxy let every request pass. That is the problem you are here
to fix. Restart the station (terminal 1) to recover.

The automatic version runs every test on a fresh station and prints a
scoreboard:

```console
python3 tools/gauntlet.py
```

On the untouched seed: **3 tests pass, 7 fail**. Each failure is either an
attack that gets through or honest traffic that the proxy breaks.

To see what the station suffers with no proxy at all:

```console
python3 tools/gauntlet.py --direct
```

## Prove it

```console
alr exec -- gnatprove -P warden.gpr
```

The summary is in `obj/development/gnatprove/gnatprove.out`. The seed proves
clean, but it also claims very little.

## Where to go next

| Read | To learn |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | what each part is, and why it is cut that way |
| [docs/TRAIL.md](docs/TRAIL.md) | the project as eight stops, each with questions and a "done when" |
| [docs/MODBUS.md](docs/MODBUS.md) | the bytes of a Modbus/TCP message |
| [docs/PLANT.md](docs/PLANT.md) | the station: its registers, its rules, its weaknesses |
| `src/net/warden_main.adb` | the whole proxy, on one screen |

In the code, comments marked `OPEN:` are the places where the seed stops and
your work starts.

## Repository map

```
src/core/      decisions: decode, policy, gate          SPARK, no I/O
src/net/       sockets, settings, journal, main         the outside world
tools/         plant.py        the pumping station and its controller
               workstation.py  the operator
               attack.py       the adversary
               gauntlet.py     the scoreboard
               modbus.py       shared Modbus/TCP helpers
docs/          trail, Modbus crib sheet, station description
```

The tools use the Python standard library only. Nothing to install.

## Built on

- GNAT 15 and GNATprove 15, both fetched by Alire
- `GNAT.Sockets` for TCP
