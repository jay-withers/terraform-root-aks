# This file is maintained automatically by "terraform init".
# Manual edits may be lost in future updates.

provider "registry.terraform.io/azure/azapi" {
  version     = "2.13.0"
  constraints = "~> 2.0, ~> 2.4, ~> 2.9, ~> 2.11, ~> 2.12"
  hashes = [
    "h1:0ota48QvsJrOc4ap8FRj38sqib8t6hlP7ftpFnUwH6g=",
    "h1:74q0+Cyz55Y/uUtWOZ9e7XPuz0u9MdXkSvcXwlv5HGU=",
    "h1:9mKVTDH+CfDpDHcoureJvz9z61UsXdfj1EMluX9ab2U=",
    "h1:Ce5wGdxk8qCrF55v1tWKNlqvaEIxgqZSvByEVD/cn2s=",
    "h1:LYUEAcDIKUaTcBRfKKdf/RCgV7sS6pb+jOPqjB7edbE=",
    "h1:NaAmhEceEaukKVTu2mLPu31QegWj9o/rKy1euzOJ18A=",
    "h1:T00QDiADkE8YrGljbnUpWs6qjx4lwl6Em4HTFJ/iAgU=",
    "h1:kNAXNMVKyvQbtmeGave+U1ga2FrZhKGzzKY00kLvHP0=",
    "h1:ku+P4k/aRkBgH5XkfCfk+3j/xg1XX7nkd+Qmyhq8QvM=",
    "h1:kwPFUxbutc+GXSr/OJ1QbxwS+beaMXR5GmqVBxG9Y9U=",
    "h1:lfv2YmNnD0xpO/w3KE+0YPy3PThbhRjCwzjhNErJiHM=",
    "h1:naC78CzNHWv8ORfa3UzhN0SMV8IVDxeCd+LXQA/Zjqg=",
    "h1:s+frf06rtTVsoSsuNgfr1bLZeocgI1h7ON+h8+ooAx0=",
    "zh:05df91a17cbb653627833746127d622502c3f502eee384aadb34e9dda1156ffd",
    "zh:21111155e27c9d0792a17141daf8535a688175a31a34d139110091ee596c359d",
    "zh:565a9f26141b6f67ba0672d728a596d0c3e903104ee463e7c9eb58d580561e8e",
    "zh:7afceb1d1c8fff83b442cfca0e83dfaddd5ab0c67cdf7c81e46877876416b3bb",
    "zh:8a4a723da2a241b398b2e990c505ccd7f327e848deaf2ad05a84c44af82462ab",
    "zh:a5409c46bd9c2e8571b2c4217f5fd3a2dcda6019d26b174f7430776bdda4805b",
    "zh:b2d5ca4680e7c122a01389d1bf4bb8d2e14add7871bfdc2eb8b0f09b2ce7221f",
    "zh:b4969c32ce8ed49c60c63653d70ae2fb489c4992b12140d5c6969e6f4ee85825",
    "zh:bbe4a39522cff59977e1bf623e7d95267d819ef3cf9ba0f597eb066ce1b11b70",
    "zh:c4d13147fed2fb35501dab059fb08f0fc15e55519d88c06ccc379a131885b454",
    "zh:e00639a5fc6e6f1df62451be45771d05b82be3356e1df3c84f4e3dca5523b1d4",
    "zh:e2948388d78d392b7992cc0e76d4f266545ffc8984ba458d7fa6884a5f04f376",
    "zh:feb0c5035caed5bd0bc516221669c79c22c8b387b33958659e617c5ed18dcadc",
  ]
}

provider "registry.terraform.io/azure/modtm" {
  version     = "0.4.0"
  constraints = "~> 0.3"
  hashes = [
    "h1:AZf16AqJYD0dj9TXCMim1pJlaSAY0qZOAXV5CJ02wR8=",
    "h1:QPvxep0fmss0+xUk2Im8Y1n+iRl2C9q+wmq6YWi5yIY=",
    "h1:c9NCKHh7f3D8QSjy56z+HIhhQdbR9AhQkRuqGcf/Aq4=",
    "zh:077eeaff6666bd1ee28b5c28c6613ddf162beb7a0230b84a2fe1d6d943174f8e",
    "zh:2b301bdd7031daa0afac77596fe662c359bb2dd96b681cd70e916db8637d5006",
    "zh:43c6fce946e92cc8d0f5ee6f7b8e93d2347d0520f5a53b89f28b49d7915a272f",
    "zh:5c705f69739382f88c4522dc865bf5c5a1ec42e29fb031c18ac7d744e5ec198e",
    "zh:6968bbd28ccdeefa33a77393e1695a896b02e6eeab6ca3384a371675e86587f4",
    "zh:71ea466bdb77732fc9bc1ad1d6db69f639f6ec2b9b6a91e08f3118258ae140d8",
    "zh:7d11a22b8d2ab5528b42cd3f7e11f3361ea510990c39de98d007d219c41e9979",
    "zh:ac95ecd69c6e26c342bba9d540f9123396145f20b6b1253a69149bb9d3aa717e",
    "zh:b9bb64f33932f01a8d70397208b3bcd3d03188234800b031d37cc8e6b3e98df9",
    "zh:be622fcf3dfec035b48865ccb6f0a46892dc5c2a80b0d3a895c55cc4e3509947",
    "zh:da5a8da50d6f130947153e28ea3bdcb289649ca944f8abf9dec4b11d14afbc8d",
    "zh:f38930feb8c3425efcc64bb7e9a4625faba8311587099b5386c3fc7b00f04854",
  ]
}

provider "registry.terraform.io/hashicorp/azurerm" {
  version     = "4.81.0"
  constraints = ">= 3.116.0, ~> 4.0, ~> 4.10, >= 4.60.0, >= 4.81.0, < 5.0.0, < 5.1.0"
  hashes = [
    "h1:XhToZua4gtih1Kv8RdStcfND83G4Tmb6GZFT4jEUhDU=",
    "h1:olVprUWhmFTARlydw/r7VIx4fata2gy3zsAWfPGRrhg=",
    "h1:uA4c+rHQWo793Bi8xMC+YlC6kVN06oC+bd0WNKn18cE=",
    "zh:0732e7b74264ddfa2b90ba69d01c283d3cbae9f72ed3e506c6ac92529fed7fd3",
    "zh:12afb524e232fe4e3d6161927724af5dfa4831d71edd9c174917ca9b7377bfae",
    "zh:169d619ae202c4145e02fb706fb7c3679445ab3e3ff722edbf89597517a8c92e",
    "zh:6beb95a3ef2f2d9c76abaa48e5450e90686a3fb6a47f1cb0ff7c5e94b6960151",
    "zh:705e075fb5ffc4bf66fd7cbabf1a65007a41621e80030a2c158a4c83b6046216",
    "zh:78d5eefdd9e494defcb3c68d282b8f96630502cac21d1ea161f53cfe9bb483b3",
    "zh:79a8d17fefe647040fcb9ee8821a4f09f395427c4fd49493489b9a93a9a1038e",
    "zh:8cc3f900b3774c0ae37ae42365c4579a199cf9e5edf88e476fdf5ab1048f84ea",
    "zh:dec373b9390fa95e257291acd018ed65a7d512b428645d35e22cdbe8b245a08b",
    "zh:e60f1e9fb45df6defade2855ed6e68547409ea75d30655c556adb0c08579749b",
    "zh:f901d12ec82f3f8b5880a27b5cbcd7bd0d97e60c9367a2d7ed82fdd1157b39ff",
    "zh:facf68ea5bf0f2b8ba720e7fba5f86492e1d4c591100460bb91c3f79f391f4b6",
  ]
}

provider "registry.terraform.io/hashicorp/random" {
  version     = "3.9.1"
  constraints = ">= 3.3.2, >= 3.5.0, ~> 3.5, ~> 3.6, >= 3.6.2, < 4.0.0"
  hashes = [
    "h1:0rmWNCsP90oLS9KtLiqcNmkRzsaOZD95THXyuGYUfOM=",
    "h1:4AN630toDK+4Is2MQcbGA37yR56nIEDPO0qv8ivZD2M=",
    "h1:7uiStw0Rl9KOdX5UNMG/sp9nyadoD4LZekQTiYlYPhE=",
    "h1:9RiO3l/4iDguiVMryazTvf8ZAOAwbS0LPWl/XRo2El4=",
    "h1:AjDEYpTXfyc3CupsrJYjgxCYnqxdpCLPkaLKPiw9WTA=",
    "h1:PYbnOqRuGn4c0/Ae1f7yOS/0zvmXNHFJRZjuF4KECnM=",
    "h1:PlW+UZ4EElQF3NQwf41KQwavFujab3Czc51zu9dyVM8=",
    "h1:VGeIpAn+nL6i8a6Y1W7XIq+Z6XFIWu5al4f2PNageoo=",
    "h1:g40qr7yDmIpaur4SsK5BcOda3HSo1RJ6zHVMqN4EJ+0=",
    "h1:nozfr4CZq73d4HjubKJundX/8A+Mj282oS/hyNfjUPU=",
    "h1:uFgaD8lhFrHzFm88V3/+wypq5AzCUdzXR60vLSlZ2cI=",
    "h1:xxRd4yd9LvPiDqeiGQj7FhZHwD08tDcIToAAePfoahE=",
    "zh:05f4734c1f0be840b711b3eff259ebc5fca436784c728955b1678078466f48d7",
    "zh:0b91bf19371d012434eba1deeb6aab77158def9b39601dcbd94450b3974a2a26",
    "zh:0ee6eacd47ec00183d55d726a4b6c4ce951a199f944bf22f1aa58392ebdfa7a2",
    "zh:19388a4074b76a89a43a6c8328d7ae8ee2e7de3d346af51e80d3e6d3d12925f1",
    "zh:23e74d48c5e2ac2e823fd527f49fee9db37d32a1990c9e3bf126ead697b843eb",
    "zh:3cabf7fbd096c520064aae3aba61aba670af83ab91291a71fa1b1332929c2b7f",
    "zh:5c0a3b8af0be60be4eca12ddee385cfa8babc1ec8e98cdf9de2f2274c73eabfa",
    "zh:60b4f8a8ef18f52bf8e19215229dae408bee732825964092db7c989fd2de4097",
    "zh:7359015acfedcbd6366f2329c854cf8d3c8ca5cd0faa89d2d37db358d6eba6c5",
    "zh:78d5eefdd9e494defcb3c68d282b8f96630502cac21d1ea161f53cfe9bb483b3",
    "zh:7b38758402f0e13a1071162da28994023cd2ac676e54af350c9ffd8dfa73fa7b",
    "zh:7c7fbb8895eb75bb4de1f933e98553bd99c8d048c89a925ddba490aa5a67f7dc",
    "zh:8c2b8c6a7ccdec16b73e2fb9f3700ea097f58c592571e4c5de60c93d2301732c",
  ]
}

provider "registry.terraform.io/hashicorp/time" {
  version     = "0.14.0"
  constraints = "~> 0.9, ~> 0.13"
  hashes = [
    "h1:/hlxsUpuN/lvPTNL9+NyVGsOyRsK5NsxwFMsj5CdOp4=",
    "h1:4EThC3ocCFiFPMZQSUvSGSxoJqBcGWxMcFYmL67uS7Y=",
    "h1:Gra0WVbFgIWSbXrZNd+E4zlXsMooCSKeUTrkxqT7//c=",
    "zh:12abfd6b800e4d7fa6db7310dec8ffd440b31993861ef188c7ed5260b3073937",
    "zh:23005521e800bb19e1597bf755c5f70d675d30b685d4255001ed5fa47d9df3f1",
    "zh:2fea249b582ae97cd1cc10385187ea50993bb47c28cc5df0305e57ceaabf0a10",
    "zh:322018d3b987b7aad08697178029a2bb667bed699e88328f0c89c52a2fd41341",
    "zh:32a08e98fce2d273cb9b2c89d6c54727cc9f0a32e15bfd896be4e02cc6b48f95",
    "zh:3db89aabd0e619616bd4b0f8b373a7586dfe60feffcea12a84a0bdbc445714b3",
    "zh:7488f56c81d742dc020f29063626c8f07ca188aa97be61e7307e8d62397020a2",
    "zh:78d5eefdd9e494defcb3c68d282b8f96630502cac21d1ea161f53cfe9bb483b3",
    "zh:7cb4067f2e7559b13f7562ef722f948950901eb37834873e98360ab28f66e9d7",
    "zh:9d552c8345f61e1b7db8e725144981345f18ac1014d58d6f5ddf0928a195fffb",
    "zh:a8e69fb6b97fc9d86fb19a9f4d42abe33c4a68e700b15387ce2e17d2b9934bed",
    "zh:aeeb900eb8dd0f790c60ea5c0e0c8d42bd6e4a54f391681d4decca15b544394b",
    "zh:c239c619101a8c95e1f14061eb973c57a8d15fa0e68878ced5bbd76858ee5b79",
  ]
}

provider "registry.terraform.io/hashicorp/tls" {
  version     = "4.3.0"
  constraints = "~> 4.0"
  hashes = [
    "h1:5bCU/c+2HUh7GhclzNSH6gAuoCS4inW3obEtRAwu6WQ=",
    "h1:QO1mfwRWprT41JDGRUfpIYyFs8h63yeOsB8RfKOjNYU=",
    "h1:j/BqLS2N2AScZyotd9nZpHdieJ7e5S8y+A+ZfIu8kL8=",
    "zh:0ab58d6f8991d436c7d2dbd89ed814709b949b07ac5a54ee53b0aec1fa772a8b",
    "zh:60b347abcb56f45d97c56f14d895069cd15a83993f199777f571b79fea3642ee",
    "zh:6889be32640349230de3f23856e6f04e0e9ced4a84a27d3f552fa54684448218",
    "zh:73f8e1ecf7135033165fb14b7e8bf4d656f3ce13065ec35762ea0481975328c7",
    "zh:94ce25ee253eca0b42cae9c856b36bca8103b6453012d1b279c3623c805f2d42",
    "zh:96bc6de9fd67bc446fd11257872e1ffb1029a996ed1d65a3f6b43f6d408ad9ab",
    "zh:97c609a310a51bfd504d704e036d72064a84bf0bdb36cc08cd4cc66098212b41",
    "zh:a12c16e94533c5bd123f75032576b9dc91dd5d5ccd5f7cf331d0f2e1adc55cf8",
    "zh:c4f014f876adf7af57188795050bda5b0029d8c7d7773031102b6c36dcf1fc21",
    "zh:d9b0a21583aaa3df3a95394fb949a3c515ff71c2ff5a1fc4a73d364aa90bfca5",
    "zh:da510d22f0c6d71ad19a76406f106b782448f512375787ecfabb338ed1e311a7",
    "zh:f0e9447a9ce3a24cdaa113089e65663c836d8b9bfdb915a1c0284e0112cab5c0",
    "zh:f569b65999264a9416862bca5cd2a6177d94ccb0424f3a4ef424428912b9cb3c",
  ]
}
