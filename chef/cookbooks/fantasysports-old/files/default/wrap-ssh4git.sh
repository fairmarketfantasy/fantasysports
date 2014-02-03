#!/usr/bin/env bash
/usr/bin/env ssh -o "StrictHostKeyChecking=no" -i "/home/ubuntu/.ssh/id_rsa" $1 $2
