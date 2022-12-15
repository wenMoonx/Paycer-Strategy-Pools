'use strict'

/* eslint-disable no-console */
const {expect} = require('chai')
const {ethers} = require('hardhat')
const {shouldBehaveLikePool} = require('../behavior/paycer-pool')
const {shouldBehaveLikeStrategy} = require('../behavior/strategy')
const {deposit, timeTravel, reset} = require('../utils/poolOps')
const StrategyType = require('../utils/strategyTypes')
const PoolConfig = require('../../helper/ethereum/poolConfig')
const {setupVPool, getUsers} = require('../utils/setupHelper')

const ONE_MILLION = ethers.utils.parseEther('1000000')

describe('vWBTC Pool with Convex sBTC', function () {
  let pool, collateralToken, strategy, user1, user2, user3, feeAcct

  before(async function () {
    const users = await getUsers()
    this.users = users
    ;[, user1, user2, user3] = users
    feeAcct = users[9]
  })

  beforeEach(async function () {
    const interestFee = '1500' // 15%
    const strategyConfig = {interestFee, debtRatio: 10000, debtRate: ONE_MILLION}

    await setupVPool(this, {
      poolConfig: PoolConfig.VAWBTC,
      feeCollector: feeAcct.address,
      strategies: [
        {
          name: 'ConvexSBTCStrategyWBTC',
          type: StrategyType.CURVE,
          config: strategyConfig,
          feeCollector: feeAcct.address,
        },
      ],
    })

    pool = this.pool
    collateralToken = this.collateralToken
    strategy = this.strategies[0].instance
    await strategy.setupOracles()
    timeTravel(3600)
  })

  describe('Pool Tests', function () {
    shouldBehaveLikePool('vaWBTC', 'WBTC')
  })

  describe('Strategy Tests', function () {
    after(reset)
    shouldBehaveLikeStrategy(0, StrategyType.CURVE, 'ConvexSBTCStrategyWBTC')
  })

  describe('Convex sBTC: WBTC Functionality', function () {
    afterEach(reset)
    // This cant pass without additional test infrastructure to simulate convex
    it('Should calculate fees properly and reflect those in share price', async function () {
      await deposit(pool, collateralToken, 20, user1)
      await strategy.rebalance()
      const price1 = await pool.pricePerShare()
      // Time travel to generate earning
      await timeTravel(30 * 24 * 60 * 60)
      await deposit(pool, collateralToken, 20, user2)
      await strategy.rebalance()
      const price2 = await pool.pricePerShare()
      expect(price2).to.be.gt(price1, 'Share value should increase (1)')
      // Time travel to generate earning
      await timeTravel(30 * 24 * 60 * 60)
      await deposit(pool, collateralToken, 20, user3)
      await timeTravel(30 * 24 * 60 * 60)
      await strategy.rebalance()
      const price3 = await pool.pricePerShare()
      expect(price3).to.be.gt(price2, 'Share value should increase (2)')
    })
  })
})
