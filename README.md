# Flydigi BS2 Pro Control

by **[Mink0812](https://github.com/Mink0812)**

Control the lights and fan of a **Flydigi BS2 / BS2 Pro** laptop cooler on Windows, **without installing Flydigi Space Station**.

There's nothing to install and nothing left running in the background. It uses the Bluetooth support and PowerShell that already come with Windows 10/11. Run it when you need it and close it when you're done.

## Features

- **One-click lights off**: `BS2Pro-LED-Off.cmd` turns off the RGB strip and the gear indicator LEDs, then exits.
- **Control page in your browser** (`BS2Pro-Control.cmd`):
  - RGB light strip and gear indicator LEDs on/off
  - Lighting effects: solid colour, breathing, rainbow, with colour, brightness and speed
  - Fan gear 1–4, or a custom speed from 1300 to 4000 RPM
  - Settings: start when powered, sleep when disconnected, fan ramp

## Requirements

- Windows 10 or 11
- Windows PowerShell 5.1. It's built into Windows; PowerShell 7 is **not** needed.
- A Flydigi BS2 or BS2 Pro, **paired** in *Settings → Bluetooth & devices*

## How to use

1. Download the latest ZIP from the [Releases](../../releases) page and extract it anywhere.
2. Make sure the cooler is on and connected in *Settings → Bluetooth & devices*.
3. Pick one of the two launchers:
   - **`BS2Pro-LED-Off.cmd`**: turns all the lights off and closes.
   - **`BS2Pro-Control.cmd`**: opens the control page at `http://localhost:17865`. The page opens in its own Microsoft Edge app window. Keep the small console window open while you use it. Click **Quit** on the page to stop: the page and the console window both close.

### Windows says the file is unsafe

Files downloaded from the internet are blocked by SmartScreen the first time. Use either fix:

- Click **More info → Run anyway**, or
- Before extracting, right-click the ZIP → **Properties** → tick **Unblock** → **OK**.

The scripts are plain text. Open `bs2pro-control.ps1` in Notepad if you'd like to read the code before running it.

### Run at login (optional)

Press `Win + R`, type `shell:startup` and press Enter. Put a **shortcut** to `BS2Pro-LED-Off.cmd` in that folder.

## Files

| File | What it does |
| --- | --- |
| `BS2Pro-LED-Off.cmd` | Turns all lights off, then exits |
| `BS2Pro-Control.cmd` | Starts the control page |
| `bs2pro-control.ps1` | The actual code: Bluetooth, commands, local web server |
| `ui.html` | The control page |

## Troubleshooting

| Message | Fix |
| --- | --- |
| `No paired Flydigi BS2 cooler found` | Pair the cooler in *Settings → Bluetooth & devices*. If its name doesn't contain "FlyDigi" or "BS2", edit `$NameMatch` at the top of `bs2pro-control.ps1`. |
| `The cooler is not connected` / `Service 0xFFF0 not found` | Turn the cooler on and make sure Windows shows it as *Connected*. |
| The page says *Script stopped* | The console window was closed. Run `BS2Pro-Control.cmd` again. |
| The page doesn't open | Open `http://localhost:17865` in any browser while the console window is running. |

## Known limitations

- The tool sends commands only. It doesn't read the fan speed or the cooler's current settings.
- Fan gear numbering and the LED count used by lighting effects (10) come from community reverse engineering and haven't been confirmed on every firmware version. If gear buttons seem off by one, or effects only cover part of the strip, please open an issue.
- Custom fan speed is dropped when the script disconnects. The cooler then goes back to its saved gear.
- There's no automatic, temperature-based fan curve. A browser page can't read CPU temperature.
- Windows only.

## How it works

The cooler exposes a vendor GATT service `0xFFF0`. Commands are written to characteristic `0xFFF2` as frames:

```
5A A5 <cmd> <len> <payload...> <checksum>
len      = payload length + 2
checksum = (cmd + len + sum(payload)) & 0xFF
```

| Command | Payload | Meaning |
| --- | --- | --- |
| `0x46` | `0` / `1` | RGB light strip off / on |
| `0x48` | `0` / `1` | Gear indicator LEDs off / on |
| `0x41`, `0x47` ×31, `0x43` | effect data | Upload a lighting effect |
| `0x08` | gear | Select fan gear |
| `0x23`, `0x21`, `0x24` | RPM (little-endian) | Enter custom speed, set RPM, exit |
| `0x0C` / `0x0D` / `0x2A` | value | Auto start / auto standby / fan ramp |

`bs2pro-control.ps1` talks to the cooler through the Windows Runtime Bluetooth API. In control mode it also serves `ui.html` on `localhost` only, so other devices on your network can't reach it.

## Credits

The protocol was reverse engineered by these projects:

- [ElXreno/flydigictl](https://github.com/ElXreno/flydigictl): firmware analysis
- [Brunight/flydigi-bs2-pro-tools](https://github.com/Brunight/flydigi-bs2-pro-tools)
- [zhugeshu/Flydigi-BS2-Pro-Controller](https://github.com/zhugeshu/Flydigi-BS2-Pro-Controller)

## Disclaimer

This is an unofficial project, not affiliated with or endorsed by Flydigi. Use it at your own risk. The script refuses to send command `0xDF`, which erases the cooler's firmware.

## License

[MIT](LICENSE) © Mink0812
