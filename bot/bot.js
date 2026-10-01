// Bot AFK: entra no servidor como jogador e fica parado no ponto de cada farm de bots.json,
// para o servidor rodar o que so funciona com jogador por perto (spawn natural de mobs etc.).
//
// Regras (definidas pelo dono do servidor):
//   - so roda no PC que esta hospedando: sobe e desce junto com o Minecraft (opcao [B] do menu);
//   - modo aventura (parado nao gasta fome; os pontos sao seguros), spawnpoint no ponto exato;
//   - nome com prefixo AFK_ e time "bots" com rotulo [BOT], para ninguem confundir com jogador;
//   - so loga se o verificador (scripts/check-bot.ps1) aprovou a versao; o modo vem de runtime.json.
const path = require('path')
const fs = require('fs')
const mineflayer = require('mineflayer')
const { lerModo, opcoesDeVersao, senhaRcon, rcon, protegerMovimento } = require('./lib')

const HOST = process.env.BOT_HOST || 'mc'
const PORT = Number(process.env.BOT_PORT || 25565)
const PROXY_HOST = process.env.PROXY_HOST || 'viaproxy'   // modo "via proxy" (ViaProxy traduz a versao)
const PROXY_PORT = Number(process.env.PROXY_PORT || 25568)
const RCON_PORT = Number(process.env.RCON_PORT || 25575)
const PROPS = process.env.SERVER_PROPERTIES || '/mcdata/server.properties'
const VERIFICAR_S = 60          // de quanto em quanto tempo confere posicao e modo de jogo
const TOLERANCIA = 1.5          // blocos de folga antes de devolver o bot ao ponto

const bots = JSON.parse(fs.readFileSync(path.join(__dirname, 'bots.json'), 'utf8'))
const modo = lerModo(path.join(__dirname, 'runtime.json'))
const DESTINO = modo.via === 'proxy' ? { host: PROXY_HOST, port: PROXY_PORT } : { host: HOST, port: PORT }
const log = (nome, msg) => console.log(`[${new Date().toISOString()}] ${nome}: ${msg}`)

async function comandos (lista) {
  return rcon(HOST, RCON_PORT, senhaRcon(PROPS), lista)
}

async function configurar (b) {
  const { nome, x, y, z } = b
  await comandos([
    'team add bots',
    'team modify bots color gray',
    'team modify bots prefix "[BOT] "',
    `team join bots ${nome}`,
    `gamemode adventure ${nome}`,
    `spawnpoint ${nome} ${x} ${y} ${z}`,
    `tp ${nome} ${x + 0.5} ${y} ${z + 0.5}`
  ])
  log(nome, `configurado: aventura, time bots, spawnpoint e posicao em ${x} ${y} ${z}`)
}

function iniciar (b, espera = 10) {
  let timer = null
  let bot
  try {
    bot = mineflayer.createBot({ ...DESTINO, username: b.nome, auth: 'offline', physicsEnabled: false, ...opcoesDeVersao(modo) })
    protegerMovimento(bot, m => log(b.nome, m))
  } catch (e) {
    log(b.nome, 'nao foi possivel criar o bot: ' + e.message)
    return setTimeout(() => iniciar(b, Math.min(espera * 2, 300)), espera * 1000)
  }

  bot.once('spawn', async () => {
    log(b.nome, 'entrou no servidor')
    espera = 10
    try { await configurar(b) } catch (e) { log(b.nome, 'falha ao configurar pelo RCON: ' + e.message) }
    timer = setInterval(async () => {
      const p = bot.entity && bot.entity.position
      if (!p) return
      const longe = Math.abs(p.x - (b.x + 0.5)) > TOLERANCIA || Math.abs(p.z - (b.z + 0.5)) > TOLERANCIA || Math.abs(p.y - b.y) > TOLERANCIA
      if (longe || bot.game.gameMode !== 'adventure') {
        log(b.nome, `fora do lugar (${p.x.toFixed(1)} ${p.y.toFixed(1)} ${p.z.toFixed(1)}, ${bot.game.gameMode}); corrigindo`)
        try { await configurar(b) } catch (e) { log(b.nome, 'falha ao corrigir: ' + e.message) }
      }
    }, VERIFICAR_S * 1000)
  })

  // Morreu (nao deveria, os pontos sao seguros): renasce no spawnpoint, que e o proprio ponto.
  bot.on('death', () => { log(b.nome, 'morreu; renascendo no ponto'); setTimeout(() => bot.respawn && bot.respawn(), 2000) })
  bot.on('kicked', motivo => log(b.nome, 'expulso: ' + (typeof motivo === 'string' ? motivo : JSON.stringify(motivo))))
  bot.on('error', e => log(b.nome, 'erro: ' + e.message))
  bot.on('end', motivo => {
    clearInterval(timer)
    log(b.nome, `desconectado (${motivo}); tentando de novo em ${espera} s`)
    setTimeout(() => iniciar(b, Math.min(espera * 2, 300)), espera * 1000)
  })
}

const descr = !modo.dados ? 'automatico' : modo.via === 'proxy' ? `entra como ${modo.dados} pelo ViaProxy ${modo.viaproxy || ''}` : modo.protocolo ? `dados ${modo.dados} com protocolo ${modo.protocolo}` : `exato ${modo.dados}`
log('bot', `modo de versao: ${descr} -> ${DESTINO.host}:${DESTINO.port}`)
bots.forEach(b => iniciar(b))
