# Third-party files

This repository is licensed under the Apache License 2.0 (see `LICENSE`),
except for the files listed below, which come from other projects and keep
their own terms. The `Justfile`s, workflows and `Containerfile` skeletons
come from [ublue-os/image-template](https://github.com/ublue-os/image-template),
also Apache-2.0.

## Argon40 case scripts

- `images/nas-argon-eon/system_files/usr/share/argon/**`
- `images/nas-argon-eon/system_files/etc/argon/**`
- `images/nas-argon-eon/system_files/usr/lib/systemd/system-shutdown/argon-shutdown.sh`
- `images/my-private-os/system_files/usr/share/argon/**` (except `argonone-eepromconfig.py`, see below)
- `images/my-private-os/system_files/etc/argon/**`
- `images/my-private-os/system_files/usr/lib/systemd/system-shutdown/argon-shutdown.sh`

Source: Argon40's install scripts (<https://download.argon40.com>), with
local changes for Fedora (see git history). Copyright Argon40 Technologies.
Argon40 publishes these scripts without a licence; they are **not** covered
by this repository's Apache-2.0 licence.

## rpi-eeprom-config

- `images/my-private-os/system_files/usr/share/argon/argonone-eepromconfig.py`

Based on `rpi-eeprom-config` from <https://github.com/raspberrypi/rpi-eeprom>.

```
Copyright (c) 2019, Raspberry Pi (Trading) Ltd.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice,
   this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.
3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from this
   software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.
```

## Ergo configuration

- `images/my-private-os/system_files/usr/share/my-private-os/ergo/ircd.yaml`

Based on `default.yaml` from Ergo v2.19.1 (<https://github.com/ergochat/ergo>),
MIT licence, Copyright (c) 2012-2014 Jeremy Latt, (c) 2014-2015 Edmund Huber,
(c) 2016-2020 Daniel Oaks, (c) 2017-2020 Shivaram Lingamneni.

## kodi.service

- `images/my-private-os/system_files/usr/lib/systemd/system/kodi.service`

Adapted from <https://github.com/graysky2/kodi-standalone-service> (MIT).
