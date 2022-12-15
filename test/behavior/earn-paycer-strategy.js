'use strict'

const {deposit, timeTravel, rebalanceStrategy} = require('../utils/poolOps')
const {expect} = require('chai')
const {ethers} = require('hardhat')
const {getUsers} = require('../utils/setupHelper')
const Address = require('../../helper/ethereum/address')
const {shouldBehaveLikeUnderlyingPaycerPoolStrategy} = require('./strategy-underlying-paycer-pool')

async function shouldBehaveLikeEarnPaycerStrategy(strategyIndex) {
  let pool, strategy
  let collateralToken
  let user1, user2

  shouldBehaveLikeUnderlyingPaycerPoolStrategy(strategyIndex)
  describe(`Earn Paycer specific tests for strategy[${strategyIndex}]`, function () {
    beforeEach(async function () {
      ;[user1, user2] = await getUsers()
      pool = this.pool
      strategy = this.strategies[strategyIndex]
      collateralToken = this.collateralToken
    })

    describe('Earning scenario', function () {
      beforeEach(async function () {
        await deposit(pool, collateralToken, 20, user1)
        await rebalanceStrategy(strategy)
      })

      it('Should increase drip balance on rebalance', async function () {
    
        await deposit(pool, collateralToken, 40, user2)

        await rebalanceStrategy(strategy)
        const dripToken = await ethers.getContractAt('ERC20', await strategy.instance.dripToken())
        const dripTokenSymbol = await dripToken.symbol()
        const earnedDripBefore =
          dripToken.address === Address.WETH
            ? await ethers.provider.getBalance(user2.address)
            : await dripToken.balanceOf(user2.address)

        const EarnDrip = await ethers.getContractAt('IEarnDrip', await pool.poolRewards())
        const growToken = await ethers.getContractAt('ERC20', await EarnDrip.growToken())
        const growTokenSymbol = await growToken.symbol()

        const tokenBalanceBefore = await growToken.balanceOf(EarnDrip.address)
        const pricePerShareBefore = await pool.pricePerShare()

        await timeTravel(10 * 24 * 60 * 60)
        await rebalanceStrategy(strategy)

        const tokenBalanceAfter = await growToken.balanceOf(EarnDrip.address)
        expect(tokenBalanceAfter).to.be.gt(tokenBalanceBefore, `Should increase ${growTokenSymbol} balance in EarnDrip`)

        const pricePerShareAfter = await pool.pricePerShare()

        expect(pricePerShareBefore).to.be.eq(pricePerShareAfter,'Price per share of of EarnPool shouldn\'t increase')
  
        const withdrawAmount = await pool.balanceOf(user2.address)

        if (collateralToken.address === Address.WETH)
          await pool.connect(user2.signer).withdrawETH(withdrawAmount)
        else
          await pool.connect(user2.signer).withdraw(withdrawAmount)

        const earnedDrip =
          dripToken.address === Address.WETH
            ? await ethers.provider.getBalance(user2.address)
            : await dripToken.balanceOf(user2.address)

        expect(earnedDrip.sub(earnedDripBefore)).to.be.gt(0, `No ${dripTokenSymbol} earned`)

      })
    })
  })
}

module.exports = {shouldBehaveLikeEarnPaycerStrategy}
