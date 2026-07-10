# 🖥️ Relatório de Hardware — YAGO_RICCOMI

> Gerado em: **26/06/2026**
> Sistema: Desktop AM4 (Gigabyte B550M)

---

## 📊 Resumo Executivo

| Componente | Especificação |
|------------|---------------|
| **CPU** | AMD Ryzen 5 5600X (6 núcleos / 12 threads) |
| **GPU** | NVIDIA GeForce RTX 4060 Ti — 8 GB VRAM |
| **RAM** | 16 GB DDR4 @ 2666 MHz (2×8 GB) |
| **Placa-mãe** | Gigabyte B550M AORUS ELITE |
| **Armazenamento** | NVMe 500 GB + SSD 512 GB + HDD 1 TB |
| **SO** | Windows 11 Pro (build 26200) |
| **Rede** | Ethernet Gigabit (Realtek) |

---

## 🔧 Processador (CPU)

| Campo | Valor |
|-------|-------|
| Modelo | AMD Ryzen 5 5600X 6-Core Processor |
| Fabricante | AuthenticAMD |
| Núcleos físicos | 6 |
| Threads (lógicos) | 12 |
| Clock base | 3.701 MHz (~3,7 GHz) |
| Cache L2 | 3 MB (3072 KB) |
| Cache L3 | 32 MB (32768 KB) |
| Soquete | AM4 |

---

## 🎮 Placa de Vídeo (GPU)

| Campo | Valor |
|-------|-------|
| Modelo | NVIDIA GeForce RTX 4060 Ti |
| VRAM | 8 GB (GDDR6) |
| Versão do driver | 32.0.16.1062 |
| Resolução atual | 2560 × 1440 (QHD) |
| Taxa de atualização | 144 Hz |

---

## 🧠 Memória RAM

| Campo | Valor |
|-------|-------|
| Total instalado | 16 GB |
| Configuração | 2 × 8 GB |
| Tipo | DDR4 |
| Velocidade | 2666 MHz |
| Velocidade configurada | 2666 MHz |
| Form factor | DIMM |

> ⚠️ Os dois módulos aparecem identificados como `D4 8G` / `DIMM 0`. O fabricante não foi reportado pelo SMBIOS.

---

## 🔌 Placa-mãe e BIOS

| Campo | Valor |
|-------|-------|
| Fabricante | Gigabyte Technology Co., Ltd. |
| Modelo | B550M AORUS ELITE |
| Chipset | AMD B550 |
| Soquete | AM4 |
| BIOS | American Megatrends (AMI) — versão **F15** |
| Data do BIOS | 15/08/2022 |

---

## 💾 Armazenamento

### Discos físicos

| Modelo | Tipo | Interface | Capacidade |
|--------|------|-----------|------------|
| KINGSTON SNV2S500G | NVMe SSD | PCIe (M.2) | 500 GB |
| Lexar 512GB SSD | SSD SATA | SATA | 512 GB |
| WDC WD10EZEX-22MFCA0 | HDD 7200 RPM | SATA | 1 TB |

### Partições (uso atual)

| Unidade | Rótulo | Sistema | Capacidade | Livre | % Livre |
|---------|--------|---------|------------|-------|---------|
| C: | Windows | NTFS | 465 GB | 54,8 GB | ~12% |
| D: | SSD | NTFS | 477 GB | 214 GB | ~45% |
| E: | HD | NTFS | 931 GB | 286 GB | ~31% |
| G: | Google Drive | FAT32 | (montagem em nuvem) | 52 GB | — |

> ⚠️ A unidade **C: está com apenas ~12% livre** — recomendável liberar espaço.

---

## 🌐 Rede

| Adaptador | Tipo | Velocidade |
|-----------|------|------------|
| Realtek PCIe GbE Family Controller | Ethernet 802.3 | 1 Gbps |
| Tailscale Tunnel | VPN (mesh) | Virtual |
| Radmin VPN Ethernet Adapter | VPN | Virtual |

> ℹ️ Tailscale e Radmin são adaptadores VPN virtuais — úteis para o cenário de servidor de Minecraft descentralizado (acesso P2P entre nodes sem abrir portas no roteador).

---

## 🪟 Sistema Operacional

| Campo | Valor |
|-------|-------|
| Edição | Microsoft Windows 11 Pro |
| Versão | 10.0.26200 (build 26200) |
| Arquitetura | 64 bits (x64) |
| Nome do PC | YAGO_RICCOMI |
| Instalação do SO | 29/04/2025 |
| Último boot | 26/06/2026 13:37 |

---

## 🎯 Avaliação para o Projeto (Servidor de Minecraft)

O hardware é **excelente** para hospedar o servidor de Minecraft em Docker descrito no projeto:

- ✅ **CPU Ryzen 5 5600X** — sobra de núcleos/threads; Minecraft usa principalmente 1-2 threads pesados, o 5600X dá conta com folga inclusive com mods.
- ⚠️ **RAM 16 GB** — o `compose.yaml` reserva **4 GB** (`MEMORY: "4G"`) para a JVM. Funciona bem, mas deixa ~12 GB para SO + Docker + Syncthing. Para mundos grandes/modpacks pesados, considere aumentar para 32 GB no futuro.
- ✅ **NVMe 500 GB (C:)** — I/O rápido para chunks/world, ideal para o volume `./data`.
- ✅ **Rede Gigabit + Tailscale** — perfeito para o modelo P2P de revezamento de host via Syncthing.

> 💡 **Dica:** mantenha a pasta `./data` em um disco com bom espaço livre. A unidade **D: (SSD, 214 GB livres)** é uma candidata melhor que a **C:** (apenas ~55 GB livres) para o volume de dados do servidor.
