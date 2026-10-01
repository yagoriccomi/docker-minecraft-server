// Diz ao verificador (scripts/check-bot.ps1) o que a biblioteca instalada conhece.
// Uso: node info.js <versao-do-servidor>   -> imprime um JSON numa linha
const md = require('minecraft-data')
const alvo = process.argv[2]
const conhecidas = md.versions.pc
const entrada = conhecidas.find(v => v.minecraftVersion === alvo)
// A versao mais nova COM dados e da mesma serie (ex.: 26.x), para o modo "protocolo forcado".
const serie = alvo.split('.')[0]
const vizinha = conhecidas
  .filter(v => v.usesNetty && v.releaseType === 'release' && v.minecraftVersion.split('.')[0] === serie && v.minecraftVersion !== alvo)
  .sort((a, b) => b.version - a.version)
  .find(v => md(v.minecraftVersion))
console.log(JSON.stringify({
  mineflayer: require('mineflayer/package.json').version,
  minecraftData: require('minecraft-data/package.json').version,
  testadas: require('mineflayer/lib/version').testedVersions.slice(-3),
  protocoloAlvo: entrada ? entrada.version : null,
  temDados: !!md(alvo),
  vizinha: vizinha ? { versao: vizinha.minecraftVersion, protocolo: vizinha.version } : null
}))
