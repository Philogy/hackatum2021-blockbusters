const { ethers } = require('hardhat')
const { expect } = require('chai')
const realTeams = require('./real-teams.js')

describe('HackaTUM_NFT', () => {
  const ownerTeamId = 6
  const ownerTokenId = ownerTeamId * 4
  let owner, user1
  let hackaNft
  let teams = realTeams

  before(async () => {
    [owner, user1] = await ethers.getSigners()
    realTeams[ownerTeamId].wallet = owner.address

    const HackaTUM_NFTFactory = await ethers.getContractFactory('HackaTUM_NFT')
    const teamParticipants = teams.map(({ wallet }) => wallet)
    hackaNft = await HackaTUM_NFTFactory.deploy(teamParticipants, {
      value: ethers.utils.parseUnits('2.5')
    })
  })
  describe('initial conditions', () => {
    it('teams receive tokens', async () => {
      for (const { wallet, teamId } of teams) {
        const tokenId = teamId * 4
        expect(await hackaNft.ownerOf(tokenId)).to.equal(wallet)
      }
    })
    it('teams tokens unclaimed', async () => {
      for (const { teamId } of teams) {
        const tokenId = teamId * 4
        expect(await hackaNft.claimed(tokenId)).to.equal(false)
      }
    })
    it('team token registered', async () => {
      for (const { teamId } of teams) {
        expect(await hackaNft.teamTokensMinted(teamId)).to.equal(1)
      }
    })
    it('teams receive native balance', async () => {
      for (const { wallet } of teams) {
        if (wallet === owner.address) continue
        expect(await ethers.provider.getBalance(wallet)).to.equal(ethers.utils.parseUnits('0.1'))
      }
    })
  })
  describe('minting team tokens', () => {
    it('allows member with team token to mint', async () => {
      await hackaNft.mintForTeam(user1.address, ownerTeamId, ownerTokenId)
      expect(await hackaNft.ownerOf(ownerTeamId * 4 + 1)).to.equal(user1.address)
      expect(await hackaNft.teamTokensMinted(ownerTeamId)).to.equal(2)
    })
    it('disallows minting for other team', async () => {
      await expect(
        hackaNft.mintForTeam(owner.address, ownerTeamId - 1, ownerTokenId)
      ).to.be.revertedWith('HackaTUM_NFT: Wrong team')
    })
    it('disallows minting with not-owned token', async () => {
      await expect(
        hackaNft.mintForTeam(owner.address, ownerTeamId - 1, (ownerTeamId - 1) * 4)
      ).to.be.revertedWith('HackaTUM_NFT: Not owner')
    })
    it('allows minting with non-genesis token', async () => {
      const userTokenId = ownerTokenId + 1
      await hackaNft.connect(user1).mintForTeam(user1.address, ownerTeamId, userTokenId)
      expect(await hackaNft.ownerOf(userTokenId + 1)).to.equal(user1.address)
      expect(await hackaNft.teamTokensMinted(ownerTeamId)).to.equal(3)
    })
  })
  describe('claiming', () => {
    it('allows claiming', async () => {
      expect(await hackaNft.claimed(ownerTokenId)).to.equal(false)
      await hackaNft.claim(ownerTokenId)
      expect(await hackaNft.claimed(ownerTokenId)).to.equal(true)
    })
    it('disallows reclaiming', async () => {
      await expect(hackaNft.claim(ownerTokenId)).to.be.revertedWith('HackaTUM_NFT: Already claimed')
    })
    it('disallows claiming for others', async () => {
      await expect(hackaNft.claim(ownerTokenId + 1)).to.be.revertedWith('HackaTUM_NFT: Not owner')
    })
    it('transferring token auto-claims it', async () => {
      const userTokenId = ownerTokenId + 1
      expect(await hackaNft.ownerOf(userTokenId)).to.equal(user1.address)
      expect(await hackaNft.claimed(userTokenId)).to.equal(false)
      await hackaNft
        .connect(user1)
        ?.['safeTransferFrom(address,address,uint256)'](
          user1.address,
          owner.address,
          ownerTokenId + 1
        )
      expect(await hackaNft.ownerOf(userTokenId)).to.equal(owner.address)
      expect(await hackaNft.claimed(userTokenId)).to.equal(true)
    })
  })
  describe('saving unclaimed', () => {
    const unclaimedTeamToken = (ownerTeamId - 1) * 4
    it('disallows saving before claim deadline', async () => {
      await expect(hackaNft.saveUnclaimed(unclaimedTeamToken)).to.be.revertedWith(
        'HackaTUM_NFT: Before deadline'
      )
    })
    it('disallows non-owner from saving tokens', async () => {
      await ethers.provider.send('evm_increaseTime', [31 * 24 * 60 * 60]) // 5 days
      await expect(hackaNft.connect(user1).saveUnclaimed(unclaimedTeamToken)).to.be.revertedWith(
        'Ownable: caller is not the owner'
      )
    })
    it('allows owner to save unclaimed token', async () => {
      await hackaNft.saveUnclaimed(unclaimedTeamToken)
      expect(await hackaNft.ownerOf(unclaimedTeamToken)).to.equal(owner.address)
      expect(await hackaNft.claimed(unclaimedTeamToken)).to.equal(true)
    })
  })
})
