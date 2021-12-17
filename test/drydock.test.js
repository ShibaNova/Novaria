const { assert } = require('chai');
const { default: Web3 } = require('web3');

const DryDock = artifacts.require('DryDock')
const NovaToken = artifacts.require('NovaToken')
// const SNovaToken = artifacts.require('SNovaToken')

// const swapPenaltyMaxPeriod = 84600;
// const swapPenaltyMaxPerSNova = 30;

require('chai')
    .use(require('chai-as-promised'))
    .should()



contract('DryDock', ([owner, player1, player2, player3]) => {
    let nova, dryDock

    before(async () => {
    // load contracts
    nova = await NovaToken.new()
    dryDock = await DryDock.new(nova.address)

    // mint nova tokens to players
    await nova.mint(player1, '10000000000000000000000', {from: owner})
    await nova.mint(player2, '10000000000000000000000', {from: owner})
    await nova.mint(player3, '10000000000000000000000', {from: owner})

    // set treasury address to owner
    await dryDock.setTreasury(owner, {from: owner})

    })

    describe('DryDock Deployment', async () => {
        it('has set treasury address as the contract owner', async () => {
            const treasuryAddress = await dryDock.Treasury()
            assert.equal(treasuryAddress, owner)
        })
    })

    describe('Initial Nova Token Balances', async () => {

        it('sends 10,000 tokens to players 1 and 2, the owner should have 0', async () => {
            let result

            result = await nova.balanceOf(owner)
            assert.equal(result.toString(), '0', 'owner starts with 0 NOVA')

            result = await nova.balanceOf(player1)
            assert.equal(result.toString(), '10000000000000000000000', 'player 1 has 10,000 NOVA')

            result = await nova.balanceOf(player2)
            assert.equal(result.toString(), '10000000000000000000000', 'player2 has 10,000 NOVA')

            result = await nova.balanceOf(player3)
            assert.equal(result.toString(), '10000000000000000000000', 'player2 has 10,000 NOVA')
        })
    })
    // !!Script from here needs work
    describe('Purchase capital ships', async () => {

        it('each player purchases one of the 3 starter packs, base to super, respectively',
        async () => {
            let result
            
            // DryDock Approvals to spend NOVA
            await nova.approve(dryDock.address, '10000000000000000000000', {from: player1})
            await nova.approve(dryDock.address, '10000000000000000000000', {from: player2})
            await nova.approve(dryDock.address, '10000000000000000000000', {from: player3})
            // result = nova.allowance(player1, dryDock.address)
            // assert.equal(result.toString(), '10000000000000000000000', 'drydock can spend 10,000 NOVA for players')

            // Player1 buys basic capital ship
            await dryDock.buildCapBasic('BasicCapShip', {from: player1})
            result = dryDock.capitalShipOwner(0)
            console.log(result.toString())
            // assert.equal(result.toString(), player1, 'player1 owns capitalship ID 0')
        })
    })

})