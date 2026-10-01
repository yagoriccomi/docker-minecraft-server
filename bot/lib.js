// Pecas comuns ao bot (bot.js) e ao teste de compatibilidade (smoke.js).
const fs = require('fs')
const net = require('net')

// Modo de conexao decidido pelo verificador (scripts/check-bot.ps1), gravado em runtime.json:
//   { "dados": "26.3" }                    -> versao exata, a biblioteca conhece a versao do servidor
//   { "dados": "26.1", "protocolo": 777 }  -> usa os dados da 26.1 mas anuncia o protocolo do servidor
// Sem runtime.json, a biblioteca descobre a versao sozinha pelo ping do servidor.
function lerModo (arquivo) {
  try { return JSON.parse(fs.readFileSync(arquivo, 'utf8')) } catch { return {} }
}

// Opcoes do mineflayer.createBot para o modo escolhido. O minecraft-data guarda os dados por
// versao em cache, entao trocar o numero do protocolo aqui vale para o handshake do cliente.
function opcoesDeVersao (modo) {
  if (!modo.dados) return {}
  if (modo.protocolo) {
    const dados = require('minecraft-data')(modo.dados)
    if (!dados) throw new Error(`a biblioteca nao tem dados da versao ${modo.dados}`)
    dados.version.version = modo.protocolo
  }
  return { version: modo.dados }
}

// RCON minimo (protocolo Source): o bot usa para se configurar no servidor (modo de jogo,
// spawnpoint, time). A senha e lida do server.properties montado somente leitura.
function senhaRcon (props) {
  const txt = fs.readFileSync(props, 'latin1')
  const m = txt.match(/^rcon\.password=(.*)$/m)
  if (!m) throw new Error('rcon.password nao encontrado em ' + props)
  return m[1].trim()
}

function rcon (host, port, senha, comandos) {
  return new Promise((resolve, reject) => {
    const sock = net.connect(port, host)
    const respostas = []
    let id = 1; let buf = Buffer.alloc(0); let autenticado = false
    const pacote = (pid, tipo, corpo) => {
      const b = Buffer.from(corpo, 'utf8')
      const p = Buffer.alloc(14 + b.length)
      p.writeInt32LE(10 + b.length, 0); p.writeInt32LE(pid, 4); p.writeInt32LE(tipo, 8)
      b.copy(p, 12); return p
    }
    const proximo = () => {
      if (!comandos.length) { sock.end(); return resolve(respostas) }
      sock.write(pacote(++id, 2, comandos.shift()))
    }
    sock.setTimeout(10000, () => { sock.destroy(); reject(new Error('RCON sem resposta')) })
    sock.on('error', reject)
    sock.on('connect', () => sock.write(pacote(1, 3, senha)))
    sock.on('data', d => {
      buf = Buffer.concat([buf, d])
      while (buf.length >= 4 && buf.length >= 4 + buf.readInt32LE(0)) {
        const len = buf.readInt32LE(0); const pid = buf.readInt32LE(4)
        const corpo = buf.slice(12, 4 + len - 2).toString('utf8')
        buf = buf.slice(4 + len)
        if (!autenticado) {
          if (pid === -1) { sock.destroy(); return reject(new Error('senha do RCON recusada')) }
          autenticado = true; proximo()
        } else { respostas.push(corpo); proximo() }
      }
    })
  })
}

module.exports = { lerModo, opcoesDeVersao, senhaRcon, rcon }
