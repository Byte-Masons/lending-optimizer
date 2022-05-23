async function main() {
    const vaultAddress = '0xDd957FbBdB549B957A1Db92b88bBA5297D0BbE99';
    const Vault = await ethers.getContractFactory('ReaperVaultv1_3');
    const vault = Vault.attach(vaultAddress);
    await vault.depositAll();
    console.log('deposit complete');
  }
  
  main()
    .then(() => process.exit(0))
    .catch(error => {
      console.error(error);
      process.exit(1);
    });
  