async function main() {
  const Vault = await ethers.getContractFactory('ReaperVaultv1_4');

  const wantAddress = '0x04068DA6C83AFCFA0e13ba15A6696662335D5B75';
  const tokenName = 'USDC Tarot Crypt';
  const tokenSymbol = 'rf-t-USDC';
  const depositFee = 0;
  const tvlCap = ethers.constants.MaxUint256;

  const vault = await Vault.deploy(wantAddress, tokenName, tokenSymbol, depositFee, tvlCap);

  await vault.deployed();
  console.log('Vault deployed to:', vault.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
