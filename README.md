<div align="center">

<img src="https://r2.fivemanage.com/GPYOH8Hq4GPyAY7czrgLe/pulsarbanner.png" alt="Pulsar Framework" width="100%" />

<br/>

# PULSAR-CORE

### The framework root — the shared `plsr` interface every other resource is built on

<br/>

![Lua](https://img.shields.io/badge/Lua_5.4-2C2D72?style=flat-square&logo=lua&logoColor=white)
![FiveM](https://img.shields.io/badge/FiveM-F40552?style=flat-square)

<br/>

<sub>Enjoy the framework? A coffee helps keep active development, hardening, and support going.</sub>

<a href="https://buymeacoffee.com/pulsarframework"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 50px !important;width: 180px !important;" /></a>

<br/>

[Overview](#overview) · [Dependencies](#dependencies)

</div>

---

## Overview

Every resource in the framework depends on this one. It exposes the shared `plsr` global and the components everything else is built on — state management, callbacks, middleware, player data, database access, logging, and more. See the API reference for the full list.

> [!WARNING]
> This is the single most depended-upon resource in the framework. Changing a component's method signature here breaks every resource that calls it, not just this one — see the full API reference before touching anything under `core/`.

---

## Dependencies

- `pulsar_pwnzor` — anti-cheat check loaded alongside every resource
- `oxmysql` — external resource, not part of Pulsar — the MariaDB driver `plsr.Database` wraps

---

## License

This resource is free to use and modify under the [Pulsar Framework License](LICENSE.md). Redistribution is welcome as long as it stays free — selling this resource or any derivative of it requires written permission from the Pulsar Framework team.

---

<div align="center">

![Pulsar Framework](https://img.shields.io/badge/Pulsar-Framework-7c3aed?style=flat-square)
![Built for FiveM](https://img.shields.io/badge/Built_for-FiveM-F40552?style=flat-square)

</div>
