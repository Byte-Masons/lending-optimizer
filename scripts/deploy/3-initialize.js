async function main() {
  const vaultAddress = '0xC43BC54aefF66c16Ea26ba142Dc58682c4eFe407';
  const strategyAddress = '0x7D2F7B4001322318050Fc11aD3d1dda5d2c82d38';

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
