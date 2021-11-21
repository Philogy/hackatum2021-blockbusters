const hre = require('hardhat')
const ethers = hre.ethers

const sleep = (timeout) => new Promise((resolve) => setTimeout(() => resolve(), timeout))

const MINUTES = 60 * 1000

async function main() {
  const compounder = await ethers.getContractAt(
    'Compounder',
    '0xe0fbd4ebe081c32473fcd38d53bc84f88e4c5098'
  )
  for (let i = 0; i < 32; i++) {
    console.log(`doing compound #${i + 1}`)
    const tx = await compounder.doCompound('0xcCad7A447ffb12fFa309eE577358C18Fe73FA45c', {
      maxFeePerGas: ethers.utils.parseUnits('1.5', 'gwei'),
      maxPriorityFeePerGas: ethers.utils.parseUnits('1.5', 'gwei'),
      gasLimit: 400_000
    })
    console.log('tx: ', tx.hash)
    console.log('tx.nonce: ', tx.nonce)
    await sleep(5 * MINUTES)
  }
  console.log('done')
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('err:', err)
    process.exit(1)
  })
