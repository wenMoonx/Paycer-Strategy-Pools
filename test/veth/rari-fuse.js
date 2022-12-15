'use strict'

const {prepareConfig} = require('./config')
const {shouldBehaveLikeStrategy} = require('../behavior/strategy')
const StrategyType = require('../utils/strategyTypes')
const {ethers} = require('hardhat')
const { shouldBehaveLikePool } = require('../behavior/paycer-pool')
const ONE_MILLION = ethers.utils.parseEther('1000000')

describe('vETH Pool', function () {
  const interestFee = '1500' // 15%
  const strategies = [
    {
      name: 'RariFuseStrategyETH',
      type: StrategyType.RARI_FUSE,
      fusePoolId: 23, // Paycer Lend
      config: {interestFee, debtRatio: 9000, debtRate: ONE_MILLION},
    },
  ]
  prepareConfig(strategies)
  shouldBehaveLikePool('vEth', 'ETH')
  for (let i = 0; i < strategies.length; i++) {
    shouldBehaveLikeStrategy(i, strategies[i].type, strategies[i].name)
  }
})
