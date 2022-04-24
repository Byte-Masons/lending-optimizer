async function main() {
  const vaultAddress = '0x610B09e55ae4AFf1dE8DDBBCD79cDe7C67eEb784';
  const strategyAddress = '0xcd8699005ECA9d4d83374B04e99Fb50F3379E657';

  const Vault = await ethers.getContractFactory('ReaperVaultv1_4');
  const vault = Vault.attach(vaultAddress);

  await vault.initialize(strategyAddress);
  console.log('Vault initialized');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
