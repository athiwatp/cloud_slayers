#!/bin/bash

latest=`curl http://rightscale-vscale.s3.amazonaws.com/appliances/latest`
application_name="vscale_${1}"
admin_name="vscale-admin_${2}"
appliance_name=`echo ${application_name} | sed s/_/-/g`
vscale="http://rightscale-vscale.s3.amazonaws.com/vscale/${application_name}.xz"
vscale_admin="http://rightscale-vscale.s3.amazonaws.com/vscale-admin/${admin_name}.xz"

echo "Checking nbd partitions"
if [[ ! -e /sys/module/nbd/parameters/max_part ]]; then
	echo "--Nope, loading it"
	modprobe nbd max_part=16
fi

echo "Checking if nbd has enough partitions enabled"
if [[ `cat /sys/module/nbd/parameters/max_part` -lt 2 ]]; then
	echo "--Nope, unloading and reloading it with 16"
	rmmod nbd
	modprobe nbd max_part=16
fi

echo "Creating work folder"
mkdir /tmp/${application_name}

echo "Getting latest image"
cd /tmp/${application_name}
wget $latest
latest_name=`ls *.ova | sed s/.ova//g`

echo "Untaring ova"
tar xf ${latest_name}.ova
rm ${latest_name}.ova

echo "Converting image to qcow2"
qemu-img convert -f vmdk -O qcow2 ${latest_name}-disk1.vmdk base.qcow2
rm ${latest_name}-disk1.vmdk

echo "Mounting base image"
qemu-nbd -c /dev/nbd0 base.qcow2
mount /dev/nbd0p1 /mnt
mount -t proc proc /mnt/proc
mount -o bind /dev /mnt/dev
mount -o bind /sys /mnt/sys

echo "Creating resolv.conf"
cp /etc/resolv.conf /mnt/etc/resolv.conf

echo "Pausing so you can run:"
#echo "chroot /mnt apt-get install apt-transport-https"
#echo "and make the vmware repo https"
#echo "...also change the ovf line from vscale 2 to vscale-2"
echo "Change /etc/logrotate.d/vscale size parameter to minsize"
read

echo "Performing OS update"
chroot /mnt apt-get update
chroot /mnt apt-get -y --force-yes dist-upgrade
chroot /mnt apt-get clean all

echo "Updating appliance.version"
echo ${application_name} >> /mnt/etc/appliance.version

echo "Downloading latest packages"
wget ${vscale} -O /mnt/tmp/${application_name}.xz
wget ${vscale_admin} -O /mnt/tmp/${admin_name}.xz

echo "Cleaning up old versions"
rm /mnt/home/vscale/* -R
rm /mnt/home/vscale-admin/* -R

echo "Untarring vscale"
mkdir /mnt/home/vscale/${application_name}
chroot /mnt ln -s /home/vscale/${application_name} /home/vscale/current
chroot /mnt tar xf /tmp/${application_name}.xz -C /home/vscale/current

echo "Untarring vscale-admin"
mkdir /mnt/home/vscale-admin/${admin_name}
chroot /mnt ln -s /home/vscale-admin/${admin_name} /home/vscale-admin/current
chroot /mnt tar xf /tmp/${admin_name}.xz -C /home/vscale-admin/current

echo "Unpacking and activating applications"
echo "cd /home/vscale/current && ./unpack.sh && ./activate.sh" > /mnt/tmp/unpack.sh
echo "cd /home/vscale-admin/current && ./unpack.sh && ./activate.sh" >> /mnt/tmp/unpack.sh
chmod +x /mnt/tmp/unpack.sh
chroot /mnt /tmp/unpack.sh

echo "Removing resolv.conf"
rm /mnt/etc/resolv.conf

echo "Cleaning up disk (this may take a while)"
rm /mnt/tmp/* -R
dd if=/dev/zero of=/mnt/tmp/zero bs=4M
rm /mnt/tmp/zero

echo "Unmounting disk"
umount /mnt/proc
umount /mnt/dev
umount /mnt/sys
umount /mnt
qemu-nbd -d /dev/nbd0

echo "Getting a thin disk"
qemu-img convert -f qcow2 -O qcow2 base.qcow2 ${appliance_name}-disk1.qcow2
rm base.qcow2

echo "Stream optimizing vmdk"
qemu-img convert -f qcow2 -O vmdk -o subformat=streamOptimized ${appliance_name}-disk1.qcow2 ${appliance_name}-disk1.vmdk
#rm ${appliance_name}-disk1.qcow2

echo "Switching vmdk version"
printf '\x03' | dd conv=notrunc of=${appliance_name}-disk1.vmdk bs=1 seek=$((0x4))

echo "Moving files around"
mv ${latest_name}.ovf ${appliance_name}.ovf
rm ${latest_name}.mf

echo "Updating ovf"
vmdk_size=`ls -l ${appliance_name}-disk1.vmdk | awk '{ print $5 }'`
sed -i s/${latest_name}/${appliance_name}/g ${appliance_name}.ovf
sed -i s/ovf:size=\"[0-9]*\"/ovf:size=\"${vmdk_size}\"/g ${appliance_name}.ovf


echo "Checksumming files"
vmdk_sha1=`sha1sum ${appliance_name}-disk1.vmdk  | awk '{ print $1 }'`
ovf_sha1=`sha1sum ${appliance_name}.ovf  | awk '{ print $1 }'`
echo "SHA1(${appliance_name}.ovf)=${ovf_sha1}" > ${appliance_name}.mf
echo "SHA1(${appliance_name}-disk1.vmdk)=${vmdk_sha1}" >> ${appliance_name}.mf

echo "Creating ovf"
tar cvf ${appliance_name}.ova ${appliance_name}.ovf ${appliance_name}.mf ${appliance_name}-disk1.vmdk

echo "Giving ova to Bill"
mv ${appliance_name}.ova /home/hrich/
chown hrich:hrich /home/hrich/${appliance_name}.ova 

echo "Cleaning up junk"
#rm /tmp/${application_name} -R
