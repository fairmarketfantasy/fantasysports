default['aws'] = {}
default['aws']['region'] = "us-west-2"

default['easternpeak']['roles'] = ['WEB'] # WEB or WORKER

default['easternpeak']['rails_prefix'] = 'webapp/'

default['easternpeak']['services']['WEB'] = ['puma']
default['easternpeak']['services']['WORKER'] = []

default['easternpeak']['rubies'] = ['ruby-2.0.0-p195']

APP_NAME = 'fantasysports'

override['aws']['load_balancer_names'] = {
 "staging" => 'fairmarketfantasy-staging',
 "production" => 'fairmarketfantasy'
}
override['aws']['key'] = "AKIAJXV4UPD3IV4JK6DA"
override['aws']['secret'] = "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"
override['aws']['pem'] = <<-EOF
-----BEGIN RSA PRIVATE KEY-----
MIIEowIBAAKCAQEArt6zdB5WWHEMBKdnCLBPBZ1z3n9NKKtkHJQ9CiH8xxq7q8GFqp0ICUUMwZQI
PMfL2rcTvE2nv4ANYSuSU25ti8fMf4fzcqaoPbplEZA1t2ezT8vl1ghWR5r817Xdr5mjDSuo1ocB
1VZiWP5Q5+IA1zys5NSHIq9E3RhnGFwfN+eeB8okj3LQdp/YikAAmS7UxCEuRNm893ED/elXCm6k
GZ5c8GMAGeKjnWbJtL9G/IxT/Um4OoqRhelUWpA1lubm7YqZavhTTftkCcOEu9PDhHH5JDN6FNFb
70DFJl0JRsRoDUeDpdLS1MHCc3YqoFA7Fa+o4jspEIAlQIlzZwK3AQIDAQABAoIBAGoEoL3UqrrC
BuxHZcMxySb5V8dcXLY8etyMzxj2lB9OSNuP328Z90ZPc7Vk/z2CUEhQ2IlAd2Q1yWbRGMy2VXn6
bzQeg21ONw/9ksr8KGUCXQcS8kw6D70n7QUGwNl2hxE0GA/AGE90KPoVbY24SpQzuAqgAzH3GwQE
iHSPXWnxY8q23H8Kfg4YGkQLP8ghyonnyGfAfvWD4VMpueBibDVyuiJ/G8dUcIGRc7+NnsHG+2DK
IDJC01NXXoS7mM2kCDdwV8z0pr15ZUF/lBl3pArurtgfFbv6yMh7guyBa8Rg2OqL4sNGO11Z5pfj
tpdCtExhWjUIX8nubEj3IpE+1WUCgYEA6mPL4dr1G7My8VvypbR8df1wjwAyehFT60R0J6sgfz+w
blTQl0T6aGE8fJuv7iy2IOQJ7eVMKvXdMLO1DRLU67BHT4iNnR3vX7otL7rhvAQyh5RPKZv4wma2
YRWl3ZbKKlQMQN/OwzGaQ5jfRD2yzhXSI++iRJARLTJ7WUc8qmMCgYEAvv4U4W+DJLT0EY46kYB3
NMn8lvJiHEKVsP3je42+mKvu5rUG05BOmvph5VVOXtO637IEHYXJBKWxAqF2aXW6qqxEDB6ui60I
sakiGlBlVH9mLIhwEGiobUmaeFJulPyc9RUixNtV94fAHio+DDtKl0PaqvCIH2HixIpiEgDjxEsC
gYAi3BLPlXQM2ZsDAIzXDj/QgJAEBKB9PSSBAh5QZAgiRMOltSGMzep8KbIISlNhFe9EdwXvBsJM
RWLPQnrz5dAa+Y2xi3qcWn5me1cLGT1HbExjk7AuXQ8jQolvaPvROAL7RqLH50FmEHOECDF0gcSd
F+u4AoTcs5yKX06vGYQxRwKBgAGdUDvfn3It/Wowk5orRdayZmo4PlAS2AUZAFVJC3Vq7qgQm7Aq
Jh/1QeKYaAMxMwE1FgfR27MoW2i0SLX3gs5yili34a3Ylpw528nxKAog0ZJKzPe2isXxu1aNC9ZC
lGkV9qdHW2CuSxd2L/QWhDjnH/AV/HCXeT1EFjQkwcglAoGBALt1SYJtdCKdI11SjMTdPqTa0Dia
bct7bEQ7t7OA7VE1VItjNPFgewJ6mgBhRPHoxVgfYSGdSrusU2Z2T0/gHocUAoX8d927n8UthF6u
EeQRzRKjWfaE3gP/+COE6LXctFyznzWONkqZNRiCBeH4DYi3scNT6QyCNIgvNe0V/piq
-----END RSA PRIVATE KEY-----
EOF

override['easternpeak']['app_name'] = APP_NAME
override['easternpeak']['database']['database'] = APP_NAME
override['easternpeak']['database']['username'] = APP_NAME
override['easternpeak']['database']['password'] = 'F4n7a5y'
override['easternpeak']['database']['master_url'] = '54.213.46.254'

override['easternpeak']['services']['WEB'] = ['puma']
override['easternpeak']['services']['WORKER'] = ['datafetcher', 'markettender']

override['easternpeak']['ssh_key.pub'] = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDJlQy3RFRx7s+XQZCkZFQYaVqg1vxXlZCU4kZjqG2uXAK6cxznxs+aj/OicvsOHngtUfiZhMYPyEFS9TiM04vMOu246FGVN3CXTlT9U8v8MbIlTMnMUQ/WYG+Y3oSzZp1cHvmYoINJXk++iVNsEUGFF3TBgh1MJz1ZdcTf7XbrAtOmwIQ5LvW8MGVHA9neoywwzmxNl6AnOT8SyKTxMSii10+xqUbCP3/Sz1pcPmk03ZGqGsqNGIpK+cM/DBjMrGVwZNADM9fzgC3/BmdkacVfJRHsYG5Op7IJw8hhlWmFrzG/nwpkfSrzyEy+rIgUCNNReh/yJxJJutq9D2OOVd4T fantasysport@easternpeak.com"
override['easternpeak']['ssh_key'] = <<-EOF
-----BEGIN RSA PRIVATE KEY-----
MIIEpQIBAAKCAQEAyZUMt0RUce7Pl0GQpGRUGGlaoNb8V5WQlOJGY6htrlwCunMc
58bPmo/zonL7Dh54LVH4mYTGD8hBUvU4jNOLzDrtuOhRlTdwl05U/VPL/DGyJUzJ
zFEP1mBvmN6Es2adXB75mKCDSV5PvolTbBFBhRd0wYIdTCc9WXXE3+126wLTpsCE
OS71vDBlRwPZ3qMsMM5sTZegJzk/Esik8TEootdPsalGwj9/0s9aXD5pNN2RqhrK
jRiKSvnDPwwYzKxlcGTQAzPX84At/wZnZGnFXyUR7GBuTqeyCcPIYZVpha8xv58K
ZH0q88hMvqyIFAjTUXof8icSSbravQ9jjlXeEwIDAQABAoIBAQCbPc1AKkA6SebX
Hqgs4hMdha1E5qwJK2bgMe5xe1mUiMmVG2esW6Cv8KJ5fcE4W2DDzjf8ypLZvqgI
Ik+9rIEh9FP1Lfz+RGbSL4ImYe1bOE5wiVVzow3mU/g9q0hY/PK86iHgV+UjkJ0r
KIj1Vci2nZzOFc1IQ4PsrFTE+xS04Oamw33PNUOiu70+N8al7fPIodlujvKkD165
jhScs/vOutf+arTeqB8FVOFS2s4enoYGLjAz3W5dsj7DXI1GGFNU2FH6jM+4Gmu6
taF6gQwMeNBNPFO3b1My/YSN2pbwDHcaA30hFSFhiTFMgoLlDb4WqWvmrl/Wgxhd
oKsA4wz5AoGBAPPWpEeEE+GR6rGHowfyiDyDAqIXE/ZyUFAKCb0lu2OOi519+7Yx
pTxiGb9q/9F5u8Tn76dohIdJr2gA34Bsp5zlcgNA30VW47xpa7sWKlZBJ8zIA9av
yZNI9Hx+CPc3UKEXewzQQbBMxHI3hHXyOaTmZfP4G5H70NO8hfeMQLS9AoGBANOi
4CItGp40ogbcdlOvtlsHims2mT6D8pzUPoGlfINn14x6e40ZQ3GiwJ5odMto4K3u
V2VBATcoLl7i/9wuqwNYGehVFLT/LHxFWYZHTmtunOtadXOS0igYNzab6Gl3kvXY
W/OdQnN4yfxKR9yH809diIvCkEd0mvuFHo/v2lMPAoGBAJGYbGc3eheKZTSz5Kju
LGLVZ1EZrpXNFB92nvIOAaIkj0Du5MmZQyyW9wDRBwcxROkCBJtVUSzm1pGnU8z/
E+YfKsC+j5J7m2f5GpaPWaA/L2CbXY9nT1lein17VCcpJD/MIXE5OL/oVrRMag9z
HvBTkjTmxK+aSMrlGqkBWfGRAoGBAJyiqtKAoXfAKr97QhR0MzoyXY82bLspO1I5
gD3CNmKnY5A0QudOcG1VcMyNMQwvhkMU6RgmwXiKQ6+0wHu9CpNCDIK5HcdMKSec
yEKq2e6HgppqbA1q+CH2sj63q48Lkfhk9sFafgkquAwDCia9dCYkauBN0y0fr2lC
wDj145efAoGAGiklx2ZUQR4IBsGpCe3rQyIZuCkbiHFW5iRSuInHQ8DuJNtTWCjN
pB6LdtHtcW8pW417mGGJIA0z/LtdctuhI7UehSEFNpLjzcqzFqv7DAgiUTDEBzhT
2DScfeRX8jyNZ9gOtOntr1rW2xnB+H+vVvectqI+G1wx/fOknb/EEkw=
-----END RSA PRIVATE KEY-----
EOF
