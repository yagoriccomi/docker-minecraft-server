// Teste de compatibilidade usado por scripts/check-bot.ps1, SEMPRE contra um servidor
// descartavel (nunca o mundo real). Sai com codigo 0 se o bot entrou e ficou conectado
// por FICAR_S segundos; codigo 1 caso contrario, com o motivo na ultima linha.
//
// Uso: node smoke.js <host> <porta> [dados] [protocolo]
const mineflayer = require('mineflayer')
const { opcoesDeVersao, protegerMovimento } = require('./lib')

const [host, porta, dados, protocolo] = process.argv.slice(2)
const FICAR_S = 20
const LIMITE_S = 90
const modo = dados ? { dados, protocolo: protocolo ? Number(protocolo) : undefined } : {}

let fim = false
const sair = (cod, msg) => { if (fim) return; fim = true; console.log((cod ? 'FALHOU: ' : 'OK: ') + msg); process.exit(cod) }
setTimeout(() => sair(1, `sem entrar em ${LIMITE_S} s`), LIMITE_S * 1000)

let bot
try {
  bot = mineflayer.createBot({ host, port: Number(porta), username: 'AFK_teste', auth: 'offline', physicsEnabled: false, ...opcoesDeVersao(modo) })
  protegerMovimento(bot, m => console.log('diag: ' + m))
} catch (e) { sair(1, e.message) }

bot.once('spawn', () => {
  console.log('entrou; segurando a conexao por ' + FICAR_S + ' s')
  setTimeout(() => {
    const p = bot.entity && bot.entity.position
    sair(0, `ficou ${FICAR_S} s conectado${p ? ` em ${p.x.toFixed(1)} ${p.y.toFixed(1)} ${p.z.toFixed(1)}` : ''}`)
  }, FICAR_S * 1000)
})
bot.on('kicked', m => sair(1, 'expulso: ' + (typeof m === 'string' ? m : JSON.stringify(m))))
bot.on('error', e => sair(1, e.message))
bot.on('end', m => sair(1, 'desconectado: ' + m))
