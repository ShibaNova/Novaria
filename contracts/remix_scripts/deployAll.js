(async () => {
  try {
    console.log('deploy...NovaToken')

    const metadata = JSON.parse(await remix.call('fileManager', 'getFile', 'browser/artifacts/NovaToken.json'))
    const accounts = await web3.eth.getAccounts()

    let contract = new web3.eth.Contract(metadata.abi)

    contract = contract.deploy({
      data: metadata.data.bytecode.object,
      arguments: []
    })

    newContractInstance = await contract.send({
      from: accounts[0],
      gas: 1500000,
      gasPrice: '30000000000'
    })
    console.log(newContractInstance.options.address)
  } catch (e) {
    console.log(e.message)
  }

  try {
    console.log('deploy...Treasury')
    const accounts = await web3.eth.getAccounts()
    const tMetadata = JSON.parse(await remix.call('fileManager', 'getFile', 'browser/artifacts/Treasury.json'))

    let contract = new web3.eth.Contract(tMetadata.abi)

    contract = contract.deploy({
      data: tMetadata.data.bytecode.object,
      arguments: [newContractInstance.options.address, newContractInstance.options.address]
    })

    newContractInstance = await contract.send({
      from: accounts[0],
      gas: 1500000,
      gasPrice: '30000000000'
    })
    console.log(newContractInstance.options.address)
  } catch (e) {
    console.log(e.message)
  }

  try {
    console.log('deploy...Map')
    const accounts = await web3.eth.getAccounts()
    const mMetadata = JSON.parse(await remix.call('fileManager', 'getFile', 'browser/artifacts/Map.json'))

    let mContract = new web3.eth.Contract(mMetadata.abi)

    contract = mContract.deploy({
      data: mMetadata.data.bytecode.object,
      arguments: []
    })

    newContractInstance = await contract.send({
      from: accounts[0],
      gas: 15000000,
      gasPrice: '70000000000'
    })
    console.log(newContractInstance.options.address)
  } catch (e) {
    console.log(e.message)
  }

  try {
    console.log('deploy...Fleet')
    const accounts = await web3.eth.getAccounts()
    const fMetadata = JSON.parse(await remix.call('fileManager', 'getFile', 'browser/artifacts/Fleet.json'))

    let fContract = new web3.eth.Contract(fMetadata.abi)

    contract = fContract.deploy({
      data: fMetadata.data.bytecode.object,
      arguments: []
    })

    newContractInstance = await contract.send({
      from: accounts[0],
      gas: 15000000,
      gasPrice: '70000000000'
    })
    console.log(newContractInstance.options.address)
  } catch (e) {
    console.log(e.message)
  }
})()