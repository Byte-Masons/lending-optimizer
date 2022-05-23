async function main() {
  const vaultAddress = '0xDd957FbBdB549B957A1Db92b88bBA5297D0BbE99';
  const ERC20 = await ethers.getContractFactory('@openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20');
  const wantAddress = '0xB12BFcA5A55806AaF64E99521918A4bf0fC40802';
  const want = await ERC20.attach(wantAddress);
  await want.approve(vaultAddress, ethers.utils.parseEther('100'));
  console.log('want approved');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
