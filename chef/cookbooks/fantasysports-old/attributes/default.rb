APP_NAME = 'fantasysports'

# Rails
default[APP_NAME]['root'] = '/mnt/www/fantasysports'
default[APP_NAME]['rails']['env'] = 'production'
#default['env'] = {'RAILS_ENV' => 'production'}

# Services
default[APP_NAME]['services'] = ['puma', #'datafetcher', 
                                 'markettender']


# DB
default[APP_NAME]['database']['database'] = APP_NAME
default[APP_NAME]['database']['username'] = APP_NAME
default[APP_NAME]['database']['password'] = 'F4n7a5y'

default[APP_NAME]['rubies'] = ['ruby-2.0.0-p195']


# TODO: Drop these in data bags
default[APP_NAME]['ssh_key.pub'] = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDr72sQ0tRhrnKVloG0eXa0LWvnYMQd267HQcZH8d7T1jkd0ZU66qFQuEc4AmJ/SpLCzKLrNwlPYPqgDPJA0sxrJNLC7dsz5OKYIaUVijs1sFoz5pkaeELGXyHZw8MQsvBp8S8rfoP7GBKf0h8jZEDljrIWPm5Y3+CO7W3Ee6mugjTsOltdzwaXLt14lzeg8AeMqTNJ8DwLordXUQIKf47v0g0FhYhgFg/DwtHzLKYgTvGmy7GtLpctZ0w2ioQxZhwSvjfy2T7j7s0thVVyvEFqtXdALtiknaikpG4JjjcQBnornvlAh6yGuGBNDQRdI3XOsqAyjVHRbLheDS0OyUtB ubuntu@ip-172-31-38-242"
default[APP_NAME]['ssh_key'] = <<-EOF
-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEA6+9rENLUYa5ylZaBtHl2tC1r52DEHduux0HGR/He09Y5HdGV
OuqhULhHOAJif0qSwsyi6zcJT2D6oAzyQNLMayTSwu3bM+TimCGlFYo7NbBaM+aZ
GnhCxl8h2cPDELLwafEvK36D+xgSn9IfI2RA5Y6yFj5uWN/gju1txHuproI07Dpb
Xc8Gly7deJc3oPAHjKkzSfA8C6K3V1ECCn+O79INBYWIYBYPw8LR8yymIE7xpsux
rS6XLWdMNoqEMWYcEr438tk+4+7NLYVVcrxBarV3QC7YpJ2opKRuCY43EAZ6K575
QIeshrhgTQ0EXSN1zrKgMo1R0Wy4Xg0tDslLQQIDAQABAoIBAQDCK9hBkEGZ4qgK
1EMK9KvsvTUAx3Kf4ByHgGpe64Andzaqg8H9Kvx4IjD6t3u4pvcBusiaLEFNQtMA
xabaEqKJy1RpeLfejZCvA4GJqKnyFaEm9bErR64s9D43qhTvuVSC3Cul8AlOrREm
1xcpWWjPhBCsndTS7+0vs9eSzPNo2ctEW9KLp7iLRDKWn0H5gyeZ1r0Cm2n9m4Tb
rJHNFLwEzJHUuH8P+YDW/uK/e1F+GXN3CGGEfztKOnR+c9S7NLhsogsgWFZn0Use
QXHcCAq+CpTXZuCLH+UD+6fcMtVFQzBqNFVRLNDPp3EvK2s5f00Lj+n1WvrfGtJ1
mnp0K9kBAoGBAP81bFosuzCZZlLBERt3GCA2XDYdJK5PZHinW6+vTu3ltuuh31Sc
R5IvsNltt8xMhr6mnJKTXxR0K35h3MU9cHKz7iHdS/hU0q/p45usJDuSzW1t9U8u
5ROIfuB7P0oJSbb24FG2IEgdS3RQAOGXC8fmtyskeIVaZWxSIkt70tf1AoGBAOyq
skDLpXjyyYoO2SZMS/ACPbEwUwzRtWLNMGqcnu3sXzgDiKSTAuL1Wl+Bl7Qdi6qH
6XE1cyqWC5ZGZmvgjLFWfEkbFESo5L0fukEdumRwJQGIu71RkhRLTauEAWHcxvzb
t+Xc3dojcaBRqap1ZGzsoQ9rd17BzeCpqcx3+TKdAoGAFKCLxmoRIydy5sNmD5M7
pvbd0x3d5hzSoRHdzkBcH8xOUZM+ysbq3fzuzVQZ4/BXf7dVtl8k8zFEhq2AO4zw
tsSmPaR2THcGpGNCG0X5k7sU0YBusFy49TA2GQy9G83OYHRpwxD2YP3FKHyC5bjg
oeKa8Wi8OQMKaYvl67XxX7UCgYBm55G6OtIoVOjs7qfczy/1nAPXF3wFBuonm7CB
qrgwG6cLY/32ETYgGS7CeEbOOkqQS6hlYShCTBudq9686VZDhadk4jFd6VIMKc+C
oLp7EYgFsr5vAxjRWizbdvpi4uxi5eaAPBj60I6Hdvqe84xHEFy3p7KvsPUjyqHa
FhB0wQKBgQDY9mk8kGq/Ht4a1vK0pbPW8ESpCy3q+ELOB/AKgRNHj7ZuFTjlC75E
uoJk3MLug0tei/h3+og4SUzsVfg8GHIfuIuGwlL5UNRNrH6kfXPyDGsnHVusokZ8
hxd3yH5IwI1kQRVib1+pxSfcu2yYwI6T/RY5c72R1zdBn9Z3vybB5w==
-----END RSA PRIVATE KEY-----
EOF


# SSL
override['nginx']['ssl_session_cache'] = 'shared:SSL:10M'
override['nginx']['ssl_session_timeout'] = '10m'

