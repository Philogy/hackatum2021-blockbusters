const { ethers } = require('hardhat')
const { expect } = require('chai')

const { BigNumber } = ethers

// waffle chai matcher docs
// https://ethereum-waffle.readthedocs.io/en/latest/matchers.html

describe('Bank contract', function () {
  // first signer account is the one to deploy contracts by default
  // eslint-disable-next-line no-unused-vars
  let owner

  let acc1
  let acc2
  let acc3

  let oracle
  let hak
  let bank

  // bank instances connected to accN
  let bank1
  let bank2
  // eslint-disable-next-line no-unused-vars
  let bank3

  // hak instances connected to accN
  let hak1
  let hak2
  // eslint-disable-next-line no-unused-vars
  let hak3

  let ethMagic

  async function mineBlocks(blocksToMine) {
    let startBlock = await ethers.provider.getBlockNumber()
    let timestamp = (await ethers.provider.getBlock(startBlock)).timestamp
    for (let i = 1; i <= blocksToMine; ++i) {
      await ethers.provider.send('evm_mine', [timestamp + i * 13])
    }
    let endBlock = await ethers.provider.getBlockNumber()
    expect(endBlock).equals(startBlock + blocksToMine)
  }

  beforeEach('deployment setup', async function () {
    [owner, acc1, acc2, acc3] = await ethers.getSigners()
    const oracleFactory = await ethers.getContractFactory('PriceOracleTest')
    const hakFactory = await ethers.getContractFactory('HAKTest')
    const bankFactory = await ethers.getContractFactory('VBTestBank')

    oracle = await oracleFactory.deploy()
    hak = await hakFactory.deploy()

    bank = await bankFactory.deploy(oracle.address, hak.address)
    ethMagic = '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE'

    // provide some tokens/eth to the bank to pay the interest
    let hakAmount = ethers.utils.parseEther('50.0')
    await hak.transfer(bank.address, hakAmount)
    let ethAmount = ethers.utils.parseEther('50.0')
    await bank.deposit(ethMagic, ethAmount, { value: ethAmount })

    bank1 = bank.connect(acc1)
    bank2 = bank.connect(acc2)
    bank3 = bank.connect(acc3)

    hak1 = hak.connect(acc1)
    hak2 = hak.connect(acc2)
    hak3 = hak.connect(acc3)
  })

  describe('deposit', async function () {
    it('unsupported token', async function () {
      await expect(bank.deposit(await acc1.getAddress(), 1337)).to.be.revertedWith(
        'token not supported'
      )
    })

    it('deposit hak', async function () {
      let amount = BigNumber.from(1337)
      // eslint-disable-next-line no-unused-vars
      let balanceBefore = await hak.balanceOf(await acc1.getAddress())
      await hak.transfer(await acc1.getAddress(), amount)
      await hak1.approve(bank.address, amount)
      expect(await hak.allowance(await acc1.getAddress(), bank.address)).equals(
        amount,
        'wrong allowance'
      )
      await bank1.deposit(hak.address, amount)
      expect(await bank1.getBalance(hak.address)).equals(amount, 'wrong balance')
      expect(await hak.balanceOf(await acc1.getAddress())).equals(0)
    })

    it('deposit eth', async function () {
      let amountBefore = await ethers.provider.getBalance(bank.address)
      let amount = ethers.utils.parseEther('10.0')
      await bank1.deposit(ethMagic, amount, { value: amount })
      expect(await ethers.provider.getBalance(bank.address)).equals(amountBefore.add(amount))
      expect(await bank1.getBalance(ethMagic)).equals(amount)
    })
  })

  describe('withdraw', async function () {
    it('unsupported token', async function () {
      await expect(bank.withdraw(await acc1.getAddress(), 1337)).to.be.revertedWith(
        'token not supported'
      )
    })

    it('without balance', async function () {
      let amount = BigNumber.from(1337)
      await expect(bank1.withdraw(ethMagic, amount)).to.be.revertedWith('no balance')
      await expect(bank1.withdraw(hak.address, amount)).to.be.revertedWith('no balance')
    })

    it('balance too low', async function () {
      let amount = BigNumber.from(10000)
      await bank1.deposit(ethMagic, amount, { value: amount })
      await expect(bank1.withdraw(ethMagic, amount.add(1000))).to.be.revertedWith(
        'amount exceeds balance'
      )
    })
  })

  describe('interest', async function () {
    it('100 blocks', async function () {
      let amount = BigNumber.from(10000)
      await bank1.deposit(ethMagic, amount, { value: amount })
      await bank.advanceBlocks(99)
      await expect(bank1.withdraw(ethMagic, 0))
        .to.emit(bank, 'Withdraw')
        .withArgs(await acc1.getAddress(), ethMagic, 10300)
    })

    it('150 blocks', async function () {
      let amount = BigNumber.from(10000)
      await bank1.deposit(ethMagic, amount, { value: amount })
      await bank.advanceBlocks(149)
      await expect(bank1.withdraw(ethMagic, 0))
        .to.emit(bank, 'Withdraw')
        .withArgs(await acc1.getAddress(), ethMagic, 10450)
      // (1 + 0.03 * 150/100) * 10000
    })

    it('250 blocks', async function () {
      let amount = BigNumber.from(10000)
      await bank1.deposit(ethMagic, amount, { value: amount })
      await bank.advanceBlocks(249)
      await expect(bank1.withdraw(ethMagic, 0))
        .to.emit(bank, 'Withdraw')
        .withArgs(await acc1.getAddress(), ethMagic, 10750)
      // (1 + 0.03 * 250/100) * 10000
    })

    it('1311 blocks', async function () {
      let amount = BigNumber.from(10000)
      await bank1.deposit(ethMagic, amount, { value: amount })
      await bank.advanceBlocks(1310)
      await expect(bank1.withdraw(ethMagic, 0))
        .to.emit(bank, 'Withdraw')
        .withArgs(await acc1.getAddress(), ethMagic, 13933)
      // (1 + 0.03 * 1311/100) * 10000
    })

    it('200 blocks in 2 steps', async function () {
      let amount = BigNumber.from(10000)
      // deposit once, wait 100 blocks and check balance
      await bank1.deposit(ethMagic, amount, { value: amount })
      await bank.advanceBlocks(100)
      expect(await bank1.getBalance(ethMagic)).equals(10300)

      // deposit again to trigger account update, wait 100 blocks and withdraw all
      await bank1.deposit(ethMagic, amount, { value: amount })
      await bank.advanceBlocks(99)
      await expect(bank1.withdraw(ethMagic, 0))
        .to.emit(bank, 'Withdraw')
        .withArgs(
          await acc1.getAddress(),
          ethMagic,
          10300 + // initial deposit + 100 block interest reward
            3 + // the 1 block where additional funds are deposited
            10600 // second deposit + 100 block reward on 20k
        )
    })
  })

  describe('borrow', async function () {
    it('no collateral', async function () {
      let amount = BigNumber.from(1000)
      await expect(bank1.borrow(ethMagic, amount)).to.be.revertedWith('no collateral deposited')
    })

    it('basic borrow', async function () {
      let collateralAmount = ethers.utils.parseEther('15.0')
      let borrowAmount = ethers.utils.parseEther('10.0')
      await hak.transfer(await acc1.getAddress(), collateralAmount)
      await hak1.approve(bank.address, collateralAmount)
      await bank1.deposit(hak.address, collateralAmount)
      await expect(bank1.borrow(ethMagic, borrowAmount))
        .to.emit(bank, 'Borrow')
        .withArgs(await acc1.getAddress(), ethMagic, borrowAmount, 15004)
      expect(await bank1.getCollateralRatio(hak.address, await acc1.getAddress())).equals(15004)
    })

    it('exceed borrow single borrow', async function () {
      let collateralAmount = ethers.utils.parseEther('15.0')
      let borrowAmount = ethers.utils.parseEther('12.0')
      await hak.transfer(await acc1.getAddress(), collateralAmount)
      await hak1.approve(bank.address, collateralAmount)
      await bank1.deposit(hak.address, collateralAmount)
      await expect(bank1.borrow(ethMagic, borrowAmount)).to.be.revertedWith(
        'borrow would exceed collateral ratio'
      )
    })

    it('exceed borrow multiple borrows', async function () {
      let collateralAmount = ethers.utils.parseEther('15.0')
      let borrowAmount = ethers.utils.parseEther('9.0')
      await hak.transfer(await acc1.getAddress(), collateralAmount)
      await hak1.approve(bank.address, collateralAmount)
      await bank1.deposit(hak.address, collateralAmount)
      await expect(bank1.borrow(ethMagic, borrowAmount))
        .to.emit(bank, 'Borrow')
        .withArgs(await acc1.getAddress(), ethMagic, borrowAmount, 16671)
      expect(await bank1.getCollateralRatio(hak.address, await acc1.getAddress())).equals(16671)

      await expect(bank1.borrow(ethMagic, borrowAmount)).to.be.revertedWith(
        'borrow would exceed collateral ratio'
      )
      expect(await bank1.getCollateralRatio(hak.address, await acc1.getAddress())).equals(16668)
    })

    it('max borrow', async function () {
      let collateralAmount = ethers.utils.parseEther('15.0')
      // there will be a block of interest applied to the collateral which
      // leads to the deviation from 10.0
      let borrowAmount = ethers.utils.parseEther('10.003')
      await hak.transfer(await acc1.getAddress(), collateralAmount)
      await hak1.approve(bank.address, collateralAmount)
      await bank1.deposit(hak.address, collateralAmount)
      await expect(bank1.borrow(ethMagic, 0))
        .to.emit(bank, 'Borrow')
        .withArgs(await acc1.getAddress(), ethMagic, borrowAmount, 15000)
      expect(await bank1.getCollateralRatio(hak.address, await acc1.getAddress())).equals(15000)
    })

    it('multiple borrows', async function () {
      let collateralAmount = ethers.utils.parseEther('15.0')
      let borrowAmount = ethers.utils.parseEther('3.0')
      await hak.transfer(await acc1.getAddress(), collateralAmount)
      await hak1.approve(bank.address, collateralAmount)
      await bank1.deposit(hak.address, collateralAmount)
      let collateralRatios = [50015, 25008, 16673]
      for (let i = 0; i < 3; ++i) {
        await expect(bank1.borrow(ethMagic, borrowAmount))
          .to.emit(bank, 'Borrow')
          .withArgs(await acc1.getAddress(), ethMagic, borrowAmount, collateralRatios[i])
      }
      expect(await bank1.getCollateralRatio(hak.address, await acc1.getAddress())).equals(
        collateralRatios[collateralRatios.length - 1]
      )
    })

    it('multiple borrows + max borrow', async function () {
      let collateralAmount = ethers.utils.parseEther('15.0')
      let borrowAmount = ethers.utils.parseEther('3.0')
      let ethBefore = await acc1.getBalance()
      await hak.transfer(await acc1.getAddress(), collateralAmount)
      await hak1.approve(bank.address, collateralAmount)
      await bank1.deposit(hak.address, collateralAmount)
      let collateralRatios = [50015, 25008, 16673]
      for (let i = 0; i < 3; ++i) {
        await expect(bank1.borrow(ethMagic, borrowAmount))
          .to.emit(bank, 'Borrow')
          .withArgs(await acc1.getAddress(), ethMagic, borrowAmount, collateralRatios[i])
      }
      expect(await bank1.getCollateralRatio(hak.address, await acc1.getAddress())).equals(
        collateralRatios[collateralRatios.length - 1]
      )

      // now borrow everything that's left
      await expect(bank1.borrow(ethMagic, 0)).to.emit(bank, 'Borrow')
      expect(await bank1.getCollateralRatio(hak.address, await acc1.getAddress())).equals(15000)

      // make sure we (roughly) received the expected amount of eth
      let ethAfter = await acc1.getBalance()
      let ethBorrowed = ethAfter.sub(ethBefore)
      expect(ethBorrowed).to.be.gte(ethers.utils.parseEther('10.0'))
      expect(ethBorrowed).to.be.lte(
        ethers.utils.parseEther('10.0').add(ethers.utils.parseEther('0.005'))
      )
    })
  })

  describe('repay', async function () {
    it('nothing to repay', async function () {
      let amount = BigNumber.from(1000)
      await expect(bank1.repay(ethMagic, amount, { value: amount })).to.be.revertedWith(
        'nothing to repay'
      )
    })

    it('non-ETH token', async function () {
      let amount = BigNumber.from(1000)
      await expect(bank1.repay(hak.address, amount)).to.be.revertedWith('token not supported')
    })

    it('lower amount sent', async function () {
      let collateralAmount = ethers.utils.parseEther('15.0')
      let borrowAmount = ethers.utils.parseEther('10.0')
      await hak.transfer(await acc1.getAddress(), collateralAmount)
      await hak1.approve(bank.address, collateralAmount)
      await bank1.deposit(hak.address, collateralAmount)
      await expect(bank1.borrow(ethMagic, borrowAmount))
        .to.emit(bank, 'Borrow')
        .withArgs(await acc1.getAddress(), ethMagic, borrowAmount, 15004)
      let amount = BigNumber.from(1000)
      await expect(bank1.repay(ethMagic, amount, { value: amount.sub(1) })).to.be.revertedWith(
        'msg.value < amount to repay'
      )
    })

    it('repay full amount', async function () {
      let collateralAmount = ethers.utils.parseEther('15.0')
      let borrowAmount = ethers.utils.parseEther('10.0')
      await hak.transfer(await acc1.getAddress(), collateralAmount)
      await hak1.approve(bank.address, collateralAmount)
      await bank1.deposit(hak.address, collateralAmount)
      await expect(bank1.borrow(ethMagic, borrowAmount))
        .to.emit(bank, 'Borrow')
        .withArgs(await acc1.getAddress(), ethMagic, borrowAmount, 15004)
      let amountDue = borrowAmount.add('5000000000000000')
      await expect(bank1.repay(ethMagic, BigNumber.from(0), { value: amountDue }))
        .to.emit(bank, 'Repay')
        .withArgs(await acc1.getAddress(), ethMagic, 0)
    })

    it('repay partial amount', async function () {
      let collateralAmount = ethers.utils.parseEther('15.0')
      let borrowAmount = ethers.utils.parseEther('10.0')
      await hak.transfer(await acc1.getAddress(), collateralAmount)
      await hak1.approve(bank.address, collateralAmount)
      await bank1.deposit(hak.address, collateralAmount)
      await expect(bank1.borrow(ethMagic, borrowAmount))
        .to.emit(bank, 'Borrow')
        .withArgs(await acc1.getAddress(), ethMagic, borrowAmount, 15004)
      let amountToRepay = ethers.utils.parseEther('4.0')
      // eslint-disable-next-line no-unused-vars
      let remainingDebt = await expect(
        bank1.repay(ethMagic, amountToRepay, { value: amountToRepay })
      )
        .to.emit(bank, 'Repay')
        .withArgs(
          await acc1.getAddress(),
          ethMagic,
          borrowAmount.sub(amountToRepay).add(5000000000000000)
        ) // interest for 1 block)
    })
  })

  describe('liquidate', async function () {
    it('liquidates a different token than HAK', async function () {
      await expect(bank1.liquidate(ethMagic, await acc1.getAddress())).to.be.revertedWith(
        'token not supported'
      )
    })

    it('liquidates own account', async function () {
      await expect(bank1.liquidate(hak.address, await acc1.getAddress())).to.be.revertedWith(
        'cannot liquidate own position'
      )
    })

    it('collateral ratio higher than 150%', async function () {
      let collateralAmount = ethers.utils.parseEther('15.0')
      let borrowAmount = ethers.utils.parseEther('10.0')
      await hak.transfer(await acc1.getAddress(), collateralAmount)
      await hak1.approve(bank.address, collateralAmount)
      await bank1.deposit(hak.address, collateralAmount)
      await expect(bank1.borrow(ethMagic, borrowAmount))
        .to.emit(bank, 'Borrow')
        .withArgs(await acc1.getAddress(), ethMagic, borrowAmount, 15004)
      let liquidatorAmount = ethers.utils.parseEther('16.0')
      await expect(
        bank2.liquidate(hak.address, await acc1.getAddress(), { value: liquidatorAmount })
      ).to.be.revertedWith('healty position')
    })

    it('collateral ratio lower than 150%', async function () {
      let collateralAmount = ethers.utils.parseEther('15.0')
      let borrowAmount = ethers.utils.parseEther('10.0')
      await hak.transfer(await acc1.getAddress(), collateralAmount)
      await hak1.approve(bank.address, collateralAmount)
      await bank1.deposit(hak.address, collateralAmount)
      await expect(bank1.borrow(ethMagic, borrowAmount))
        .to.emit(bank, 'Borrow')
        .withArgs(await acc1.getAddress(), ethMagic, borrowAmount, 15004)
      await bank.advanceBlocks(99)
      let liquidatorEthBalanceBefore = await acc2.getBalance()
      let liquidatorHakBalanceBefore = await hak2.balanceOf(await acc2.getAddress())
      collateralAmount = ethers.utils.parseEther('15.4545')
      let liquidatorAmount = ethers.utils.parseEther('16.0')
      await expect(
        bank2.liquidate(hak.address, await acc1.getAddress(), { value: liquidatorAmount })
      )
        .to.emit(bank, 'Liquidate')
        .withArgs(
          await acc2.getAddress(),
          await acc1.getAddress(),
          hak.address,
          collateralAmount,
          liquidatorAmount.sub('10500000000000000000')
        )
      let liquidatorEthBalanceAfter = await acc2.getBalance()
      let liquidatorHakBalanceAfter = await hak2.balanceOf(await acc2.getAddress())
      expect(liquidatorEthBalanceBefore.sub(liquidatorEthBalanceAfter)).to.gte(
        BigNumber.from('10500000000000000000')
      )
      expect(liquidatorHakBalanceAfter.sub(liquidatorHakBalanceBefore)).to.equal(collateralAmount)
    })

    it('collateral ratio lower than 150% but insufficient ETH', async function () {
      let collateralAmount = ethers.utils.parseEther('15.0')
      let borrowAmount = ethers.utils.parseEther('10.0')
      await hak.transfer(await acc1.getAddress(), collateralAmount)
      await hak1.approve(bank.address, collateralAmount)
      await bank1.deposit(hak.address, collateralAmount)
      await expect(bank1.borrow(ethMagic, borrowAmount))
        .to.emit(bank, 'Borrow')
        .withArgs(await acc1.getAddress(), ethMagic, borrowAmount, 15004)
      await bank.advanceBlocks(99)
      let liquidatorAmount = ethers.utils.parseEther('10.0')
      await expect(
        bank2.liquidate(hak.address, await acc1.getAddress(), { value: liquidatorAmount })
      ).to.be.revertedWith('insufficient ETH sent by liquidator')
    })
  })
})
