## Install git

https://gitforwindows.org/

## Add Git to PATH

By default the git binaries are not set in to PATH, so add it by going to:

```
Control Panel/System and Security/System/Advanced system settings
```

Then in System Properties click on Environment Variables… and in System Variables list box scroll to Variable Path, double-click it and add at the end:

```
;C:\Program Files (x86)\Git\cmd;C:\Program Files (x86)\Git\bin;
```

## Install git-lfs

https://help.github.com/en/github/managing-large-files/installing-git-large-file-storage

## Run the following in powershell

```
cd ~\Desktop
mkdir starcraft-base-defense
cd starcraft-base-defense
git init
git remote add origin -f https://github.com/devopsec/starcraft-base-defense.git
git config core.sparseCheckout true
echo "/Build" > .git\info\sparse-checkout
git pull origin master
```

if you only want a specific build version:

```
$ver = "v1.00.01"
echo "/Build/$ver" > .git\info\sparse-checkout
```

