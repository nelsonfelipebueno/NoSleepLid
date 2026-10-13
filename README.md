# NoSleepLid — Keep your Mac awake with the lid closed

**NoSleepLid** is a tiny, free and open-source macOS menu bar app that **keeps your MacBook awake with the lid closed** — no external display, no keyboard, no mouse, no charger required. One click turns it on, one click pauses it. While the lid is shut, the screen and the keyboard backlight go dark; when you open the lid, they come back exactly as they were.

Use it to keep downloads, uploads, builds, renders, backups, SSH sessions, servers, AI agents or music running while your MacBook is closed.

> 🇧🇷 [Resumo em português](#-em-português)

---

## Contents

- [Why NoSleepLid](#why-nosleeplid)
- [Features](#features)
- [Requirements](#requirements)
- [Install](#install)
- [How to use](#how-to-use)
- [How it works](#how-it-works)
- [Security: the sudoers rule](#security-the-sudoers-rule)
- [Safety](#safety)
- [Uninstall](#uninstall)
- [FAQ](#faq)
- [Em português](#-em-português)
- [License](#license)

## Why NoSleepLid

macOS puts a MacBook to sleep the moment you close the lid. Apple's official **clamshell mode** only keeps it awake if you connect an external display, a keyboard or mouse *and* a power adapter.

The usual tricks don't solve it:

- `caffeinate` and most "keep awake" apps stop *idle* sleep, but **closing the lid still puts the Mac to sleep**.
- `sudo pmset -a disablesleep 1` does keep it awake with the lid closed — but it's easy to forget it on, it drains the battery, and the screen may stay lit inside your bag.

NoSleepLid wraps that setting in a safe on/off switch: it turns it on only while you want it, turns it off when you pause, quit, or the battery gets low, and repairs it if something crashes.

## Features

- ☕ **One-click toggle** in the menu bar (left click). Right click opens the menu.
- 💻 **Stays awake with the lid closed** — no external monitor, no clamshell setup, works on battery.
- 🌑 **Dark when closed**: built-in screen and keyboard backlight go to 0 while the lid is shut, and are restored to your previous levels when you open it.
- 🔓 **No lock screen / Touch ID prompt** when you open the lid during a session (the display never sleeps, it's just dimmed to 0). You can still lock manually with `Ctrl + Cmd + Q`.
- 🔋 **Battery guard**: turns itself off below 15% on battery and won't start below it.
- 🛟 **Self-healing**: pausing, quitting, `kill`/`pkill` and crashes all end with sleep re-enabled. If the app dies mid-session, the next launch fixes it.
- 🔑 **No password on every click**: a narrow sudoers rule allows only `pmset -a disablesleep 0|1`.
- 🪶 **Tiny and transparent**: one Swift file, no dependencies, no network access, no analytics.
- 📝 **Disk-friendly log**: one line per state change, capped at 1 MB, paused when disk space is low.
- 🚀 **Open at login** option.

## Requirements

- macOS 13 Ventura or later. Tested on macOS 27 with an Apple Silicon (M3) MacBook Air.
- Xcode Command Line Tools to build (`xcode-select --install`).
- An administrator account (once, to install the sudoers rule).

## Install

```bash
git clone https://github.com/nelsonfelipebueno/NoSleepLid.git
cd NoSleepLid
./install.sh
```

`install.sh` builds the app, copies it to `~/Applications/NoSleepLid.app`, installs the sudoers rule (asks for your password once) and opens the app. A moon icon appears in the menu bar.

To update later: `git pull && ./install.sh`.

## How to use

| Action | What happens |
|---|---|
| **Left click** the 🌙 icon | Turns on. Icon becomes ☕. Your Mac won't sleep, even with the lid closed. |
| **Left click** the ☕ icon | Pauses. Normal sleep is back. |
| **Right click** | Menu: status, battery level, Open at login, Open log, Quit. |
| ⚠︎ icon | Something needs attention (usually the sudoers rule is missing). Details in the menu. |

## How it works

When you turn it on, NoSleepLid:

1. Runs `sudo -n pmset -a disablesleep 1` — this is the only setting that stops a Mac from sleeping when the lid closes.
2. Starts `caffeinate -d -w <app pid>` — keeps the display "awake" so closing the lid doesn't trigger the lock screen. Because of `-w`, it dies automatically with the app.
3. Every second, reads `AppleClamshellState` from `IOPMrootDomain` (IOKit) to know if the lid is open or closed.
4. **Lid closed** → saves the current screen and keyboard brightness, then sets both to 0 (DisplayServices and CoreBrightness). Keeps forcing the keyboard to 0, because ambient light sensing tries to turn it back on in the dark.
5. **Lid opened** → restores the saved brightness.
6. Checks the battery (IOKit power sources) and turns itself off below 15%.

When you pause or quit, it stops the timer, kills `caffeinate`, restores brightness and runs `pmset -a disablesleep 0`.

On launch, if it finds `SleepDisabled = 1` without an active session (for example after a crash or a forced restart), it resets it to 0.

Log file: `~/Library/Logs/NoSleepLid.log`.

## Security: the sudoers rule

Changing `disablesleep` needs root. To avoid a password prompt on every click, `install.sh` creates `/etc/sudoers.d/nosleeplid`:

```
<your-user> ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1
```

- It allows **exactly these two commands**, nothing else, and only for your user.
- It is validated with `visudo` before being installed.
- Any program running as your user could also use it to toggle sleep. That is the only power it grants.
- Don't want it? Skip it: NoSleepLid falls back to the standard macOS admin password dialog each time you turn it on or off.

## Safety

- **Don't put a running MacBook in a closed bag or sleeve.** A closed laptop with no airflow can overheat. Use a hard, ventilated surface.
- NoSleepLid uses private macOS frameworks (DisplayServices, CoreBrightness) for brightness. A future macOS update could break brightness control; staying awake would still work.
- The battery guard only works while the app is running.

## Uninstall

```bash
./uninstall.sh
```

Removes the app, the sudoers rule and the logs, and runs `pmset -a disablesleep 0`.

## FAQ

### How do I keep my MacBook awake with the lid closed?
Install NoSleepLid, click the moon icon in the menu bar, and close the lid. The Mac keeps running with the screen and keyboard dark.

### Does it work without an external monitor?
Yes. That's the whole point — no external display, keyboard, mouse or charger needed.

### Does it work on battery?
Yes. It turns itself off automatically below 15% so your Mac can sleep before the battery dies.

### Why doesn't `caffeinate` keep my Mac awake when I close the lid?
`caffeinate` prevents idle sleep, but closing the lid triggers a different kind of sleep that only `pmset disablesleep` stops. NoSleepLid uses both.

### Will opening the lid ask for my password or Touch ID?
Not during a session: the display is kept awake and only dimmed to 0, so macOS doesn't lock. Lock manually with `Ctrl + Cmd + Q` if you want.

### What if the app crashes while it's on?
`caffeinate` dies with it. `disablesleep` stays on until NoSleepLid starts again, and it fixes it on launch. You can also run `sudo pmset -a disablesleep 0` yourself.

### Is it an alternative to Amphetamine, Caffeine, KeepingYouAwake or Insomnia?
It's another option, focused on one job: lid-closed awake, with a dark screen, in one click. It's open source and small enough to read in a few minutes.

### Does it collect data or use the internet?
No. No network access, no analytics, no telemetry.

---

## 🇧🇷 Em português

**NoSleepLid** é um app gratuito e open-source para a barra de menus do macOS que **mantém o MacBook ligado com a tampa fechada**, sem monitor externo e funcionando na bateria. Um clique liga, um clique pausa. Com a tampa fechada, a tela e a luz do teclado apagam (brilho 0); ao abrir, voltam ao nível anterior, sem pedir senha ou Touch ID.

- **Instalar:** `git clone https://github.com/nelsonfelipebueno/NoSleepLid.git && cd NoSleepLid && ./install.sh`
- **Usar:** clique esquerdo na lua 🌙 liga (vira ☕); clique de novo pausa. Clique direito abre o menu.
- **Proteções:** desliga sozinho abaixo de 15% de bateria; se o app fechar ou travar, o Mac volta a dormir normalmente; log pequeno e limitado.
- **Como funciona:** usa `pmset disablesleep` (o único ajuste que impede o sleep ao fechar a tampa) e `caffeinate -d`, desfazendo tudo ao pausar.
- **Segurança:** a regra de sudo libera só `pmset -a disablesleep 0|1` para o seu usuário.
- **Atenção:** não guarde o Mac ligado dentro de mochila ou capa fechada — pode superaquecer.
- **Desinstalar:** `./uninstall.sh`

## License

[MIT](LICENSE) © Nelson Bueno
