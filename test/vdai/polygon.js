'use strict'

const { prepareConfig } = require('./config')
const { shouldBehaveLikePool } = require('../behavior/paycer-pool')
const { shouldBehaveLikeMultiPool } = require('../behavior/paycer-multi-pool')
const StrategyType = require('../utils/strategyTypes')
const { BigNumber: BN } = require('ethers')
const DECIMAL18 = BN.from('1000000000000000000')
const ONE_MILLION = DECIMAL18.mul('1000000')

/* eslint-disable mocha/no-setup-in-describe */
describe('vDAI Pool', function () {
  const interestFee = '1500'
  const strategies = [
    {
      name: 'AaveStrategyPolygonDAI',
      type: StrategyType.AAVE,
      config: { interestFee, debtRatio: 4000, debtRate: ONE_MILLION },
    },
    {
      name: 'AaveStrategyPolygonDAI',
      type: StrategyType.AAVE,
      config: { interestFee, debtRatio: 4000, debtRate: ONE_MILLION },
    }
  ]
  prepareConfig(strategies)
  shouldBehaveLikePool('vDai', 'DAI')
  shouldBehaveLikeMultiPool('vDai')
})
