const DryDock = artifacts.require('DryDock')
const NovaToken = artifacts.require('NovaToken')
// const SNovaToken = artifacts.require('SNovaToken')

// const swapPenaltyMaxPeriod = 84600;
// const swapPenaltyMaxPerSNova = 30;


module.exports = async function (deployer, network, accounts) {

    await deployer.deploy(NovaToken)
    const _Nova = await NovaToken.deployed()

    // await deployer.deploy(SNovaToken, swapPenaltyMaxPeriod, swapPenaltyMaxPerSNova)
    // const _sNova = await SNovaToken.deployed()

    await deployer.deploy(DryDock, _Nova.address)
  

};
