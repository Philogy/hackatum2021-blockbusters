const hre = require('hardhat')

async function main() {
  // const bank = await hre.ethers.getContractAt('Bank', '0x046d90f1614c3732ce04d866bc9ef0ae1cdda509')
  const value = await hre.ethers.provider.getStorageAt(
    '0x046d90f1614c3732ce04d866bc9ef0ae1cdda509',

    '0x4beb52f0c589751d9d26b8aa8cd270432f415a8f1ee175bfbd877e3ff265f23f'
  )
  console.log('value: ', value)
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('err:', err)
    process.exit(1)
  })
