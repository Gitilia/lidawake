# lidawake

`lidawake` keeps a laptop awake after you close the lid. Whatever was already running keeps running, including a compile or a local agent. The screen turns off.

It is free and MIT licensed. This repository is the command-line tool. There is no separate app. The commands are the same on macOS and Linux: `lidawake on`, `lidawake off`, `lidawake status`.

Status: active.

## Run

Leave `lidawake on` in a terminal, then close the lid. Ctrl-C turns normal sleep back on. From another terminal:

```bash
lidawake off
```

`lidawake status` prints `running` and a process id, or `stopped`.

### macOS

You need a Swift compiler. `xcode-select --install` is enough if you do not have Xcode.

```bash
make
./lidawake on
```

To put the command on your `PATH`:

```bash
make install
```

The default prefix is `/usr/local`, which often asks for an admin password. If you use Homebrew:

```bash
make install PREFIX=/opt/homebrew
```

### Linux

You need systemd, which supplies `systemd-inhibit`. There is nothing to compile.

```bash
make install
lidawake on
```

`/usr/local` usually requires root on Linux. A user prefix works too:

```bash
make install PREFIX="$HOME/.local"
```

On GNOME, `lidawake` also runs `gnome-session-inhibit` when that command is installed. GNOME handles the lid itself, so the logind lock alone is not enough there.

## Config

There is no config file. `LIDAWAKE_PID_FILE` sets the pid file path. The default is `/tmp/lidawake.pid`.

## How it works

### macOS

`lidawake on` does two things until you stop it.

It calls IOKit on `IOPMrootDomain` (`kPMSetClamshellSleepState`, selector 12) so the kernel ignores lid-close sleep. That call does not need an admin password.

It also holds a `PreventUserIdleSystemSleep` assertion named `lidawake`, so the Mac does not idle-sleep after the built-in display turns off.

Every two seconds it sets the lid flag again. On Apple silicon, plugging or unplugging power can clear the flag.

Ctrl-C and `lidawake off` clear it. `kill -9` does not. If that happens, run `lidawake off`, or reboot.

`caffeinate` does not stop sleep when the lid closes. If the Mac is on power with an external display and a keyboard, macOS closed-display mode already does this.

### Linux

`lidawake on` runs `systemd-inhibit` with a block lock for `handle-lid-switch` and `idle`. logind then ignores the lid switch, and idle suspend stays off, until this process exits. There is no password prompt. If your user is not allowed to take that lock, the command exits and says so.

The lock is a file descriptor. When the process ends, including `kill -9`, the kernel closes it and the lock is gone. That differs from macOS, where `kill -9` leaves the lid flag set.

`systemctl suspend` still suspends. This command blocks the lid switch and idle suspend.

A desktop that does not use logind or GNOME for the lid will not honor the lock.

## Both

A very low battery, or the machine overheating, can still force sleep.

Leave the laptop on a hard surface. A closed lid traps heat. Do not put it in a bag while this is running.

## Tests

```bash
make test
```

On a Mac this builds the Swift command, checks the power assertion, and runs the Linux script against a stand-in for `systemd-inhibit`. On Linux it runs the script tests, and one real logind lock when the session is allowed to take one.

## License

MIT. See [LICENSE](LICENSE).
