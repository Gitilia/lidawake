# lidawake

`lidawake` keeps a MacBook awake while the lid is closed, so local work continues with the screen off. That includes compiles, downloads, and editor agents running on this machine.

Status: active.

## Run

Needs macOS on a Mac laptop, and a Swift compiler (`xcode-select --install` is enough).

```bash
make
./lidawake on
```

Leave that process running, then close the lid. The display goes dark. The Mac stays awake. Restore normal sleep with Ctrl-C, or from another terminal:

```bash
./lidawake off
```

Install the binary onto `PATH`:

```bash
make install
```

The default prefix is `/usr/local`. Homebrew's prefix is writable for many accounts without extra privileges:

```bash
make install PREFIX=/opt/homebrew
```

Check whether a session is active:

```bash
lidawake status
```

## Config

No config file and no secrets. `LIDAWAKE_PID_FILE` overrides the pid file path. The default is `/tmp/lidawake.pid`.

## What it changes

While `lidawake on` is running, two things stay in effect:

1. An IOKit call on `IOPMrootDomain` (`kPMSetClamshellSleepState`, selector 12) tells the kernel to ignore lid-close sleep. No admin password.
2. A `PreventUserIdleSystemSleep` assertion named `lidawake` stops idle sleep after the built-in display turns off.

The process re-applies the lid override every two seconds. Plugging or unplugging power can clear that flag on Apple silicon.

The lid flag is sticky. A normal exit or `lidawake off` clears it. `kill -9` does not. If that happens, run `lidawake off`. A reboot clears it too.

Low battery and a thermal emergency can still sleep the Mac.

Keep the machine on a hard surface with airflow. A closed lid traps heat. Do not leave a running Mac in a bag.

`caffeinate` does not cover lid-close sleep. With an external display, keyboard, and power, macOS already has closed-display mode and this tool is unnecessary.

## Develop

```bash
make test
```

The test starts a session, checks the power assertion, refuses a second session, then restores lid sleep.

## License

MIT. See [LICENSE](LICENSE).
