# lidawake

`lidawake` is a macOS command that keeps a MacBook awake after you close the lid. Whatever was already running keeps running, including a compile or a local agent. The screen turns off.

It is free and MIT licensed. This repository is the command-line tool. There is no separate app.

Status: active.

## Run

You need macOS on a laptop and a Swift compiler. `xcode-select --install` is enough if you do not have Xcode.

```bash
make
./lidawake on
```

Leave that process in the terminal, then close the lid. Ctrl-C turns normal sleep back on. From another terminal:

```bash
./lidawake off
```

To put the command on your `PATH`:

```bash
make install
```

The default prefix is `/usr/local`, which often asks for an admin password. If you use Homebrew:

```bash
make install PREFIX=/opt/homebrew
```

`lidawake status` prints `running` and a process id, or `stopped`.

## Config

There is no config file. `LIDAWAKE_PID_FILE` sets the pid file path. The default is `/tmp/lidawake.pid`.

## How it works

`lidawake on` does two things until you stop it.

It calls IOKit on `IOPMrootDomain` (`kPMSetClamshellSleepState`, selector 12) so the kernel ignores lid-close sleep. That call does not need an admin password.

It also holds a `PreventUserIdleSystemSleep` assertion named `lidawake`, so the Mac does not idle-sleep after the built-in display turns off.

Every two seconds it sets the lid flag again. On Apple silicon, plugging or unplugging power can clear the flag.

Ctrl-C and `lidawake off` clear it. `kill -9` does not. If that happens, run `lidawake off`, or reboot.

A very low battery, or the Mac overheating, can still force sleep.

Leave the laptop on a hard surface. A closed lid traps heat. Do not put it in a bag while this is running.

`caffeinate` does not stop sleep when the lid closes. If the Mac is on power with an external display and a keyboard, macOS closed-display mode already does this.

## Tests

```bash
make test
```

The test starts a session, checks the power assertion, checks that a second `on` is refused, and then restores sleep.

## License

MIT. See [LICENSE](LICENSE).
