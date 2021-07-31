#!/bin/bash
red="\033[0;31m"
green="\033[0;32m"
yellow="\033[0;33m"
normal="\033[0m"
vultr_cli="/usr/local/bin/vultr-cli"

arch=$(arch)
if [ $arch == "x86_64" -o $arch == "x64" -o $arch -o "amd64" ]; then
	arch="64"
elif [ $arch == "arm64" -o $arch == "aarch64" ]; then
	arch="arm64"
else
	arch="64"
fi

os=$(uname)
if [ $os == "Linux" -o $os == "linux" ]; then
	os="linux"
elif [ $os == "Darwin" -o $os == "darwin" ]; then
	os="macOs"
else
	echo -e "\n1、macOs\n 2、linux"
	read -p "请输入你目前的操作系统(2)：" os_choise
	case $os_choise in
		"1") os="macOs"
		;;
		"2") os="linux"
		;;
	esac
fi

install_vultr-cli () {
	local flag=0
	[ -x ${vultr_cli} ] && flag=1
	[ "$1" == "reinstall" ] && flag=0
	if [ ${flag} -eq 0 ]; then
		version=`curl -sL "https://api.github.com/repos/vultr/vultr-cli/releases/latest" | grep "tag_name" | sed -E "s/.*v(.*)\".*/\1/"`
		if [ ! $? ]; then
			read -p "无法获取版本信息，请手动输入版本号：（默认：2.7.0）" version
			if [ -z $version ]; then
				$version="2.7.0"
			fi
		fi
		echo "----------------------"
		echo "开始安装 Vultr-CLI..."
		curl -L "https://hub.fastgit.org/vultr/vultr-cli/releases/download/v${version}/vultr-cli_${version}_${os}_${arch}-bit.tar.gz" \
		| tar -zxC /usr/local/bin/
		curl -L "https://cdn.jsdelivr.net/gh/freessir/vultr-cli/.vultr-list" -o ~/.vultr-list
		[ -x ${vultr_cli} ] && echo -e "${yellow}Vultr-CLI 安装成功！${normal}"
	fi
}

import_api-key () {
	local flag=0
	[ -f ~/.vultr-cli.yaml ] && flag=1
	[ "$1" == "reimport" ] && flag=0
	if [ ${flag} -eq 0 ]; then
		local current_api_key=`sed -r 's/api-key:[:blank:]*//' ~/.vultr-cli.yaml`
		[ -n ${current_api_key} ] && echo -e "如有必要可保存当前API KEY: ${yellow}${current_api_key}${normal}"
		read -p "请输入你的Vultr API KEY：" api_key
		[ -n $api_key ] && echo "api-key: $api_key" > ~/.vultr-cli.yaml || echo -e "{$red}输入的 API KEY 有误！{$normal}"
		echo -e "正在验证你的API KEY，请稍后...\n"
		$vultr_cli instance list
		if [ $? ]; then
			echo "验证成功，你输入的 API KEY 有效！"
		else
			ip=$(curl -s "ip.sb")
			echo "验证失败！请确保你的 API KEY 正确，并已将当前ip地址（$ip）加入到 Vultr 白名单内。"
		fi
	fi
}

create_vultr_key () {
	[ -f ~/.ssh/id_rsa_vultr ] && mv ~/.ssh/id_rsa_vultr ./id_rsa_vultr.bak \
	&& echo "----------------------" && echo -e "已将上次的密钥保存在当前目录下 ${red}id_rsa_vultr.bak${normal} 中，注意保存。"
	echo -e "${green}开始创建ssh key...${normal}"
	echo -e ~/.ssh/id_rsa_vultr | ssh-keygen -t rsa -f ~/.ssh/id_rsa_vultr > /dev/null
	echo -e "${green}开始导入ssh key到Vultr...${normal}"
	$vultr_cli ssh create --name ssh-cli --key "`cat ~/.ssh/id_rsa_vultr.pub`" > /dev/null
	echo -e "${green}导入成功。Vultr的SSH公钥位于：${normal}${red}~/.ssh/id_rsa_vultr${normal}"
}

list_vultr_instance () {
	local i=1
	instance_list=`$vultr_cli instance list | egrep -v '(ID|=|TOTAL)' | sed '$d' | awk '{print $1}'`
	for instance in $instance_list
	do
		local instance_info=`$vultr_cli instance get $instance | egrep -i '(^os|^ram|^disk|^vcpu|^status|^date created|^main ip|^plan|^region|^id)' \
		| sort | sed 's/$/,/' | tr -s "\t" | awk 'BEGIN{FS="\t"} {print $2}'`
		# 1 create date;
		# 2 disk;
		# 3 id
		# 4 ipv4;
		# 5 os;
		# 6 osid;
		# 7 plan;
		# 8 ram;
		# 9 region;
		# 10 status;
		# 11 cpu;
		#local create_time=`echo $instance_info | awk 'BEGIN{FS=","} {print $1}'`
		#local disk=`echo $instance_info | awk 'BEGIN{FS=","} {print $2}'`
		local instance_id=`echo $instance_info | awk 'BEGIN{FS=","} {print $3}' | tr -d " "`
		local ipv4=`echo $instance_info | awk 'BEGIN{FS=","} {print $4}' | tr -d " "`
		local os=`echo $instance_info | awk 'BEGIN{FS=","} {print $5}' | tr -d " "`
		local plan=`echo $instance_info | awk 'BEGIN{FS=","} {print $7}' | tr -d " "`
		#local ram=`echo $instance_info | awk 'BEGIN{FS=","} {print $8}'`
		local region=`echo $instance_info | awk 'BEGIN{FS=","} {print $9}' | tr -d " "`
		#local status=`echo $instance_info | awk 'BEGIN{FS=","} {print $10}'`
		#local cpu=`echo $instance_info | awk 'BEGIN{FS=","} {print $10}'`
		region=`cat ~/.vultr-list | sed -n "s/area:${region}=//p"`
		plan=`cat ~/.vultr-list | sed -n "s/plan:${plan}=//p"`
		echo -e ${i}、${yellow}地区：${normal}"${region}" ${yellow}ip地址：${normal}"${ipv4}" ${yellow}系统：${normal}"${os}" ${yellow}套餐：${normal}"${plan}"
		instance_id_list[$i]=${instance_id}
		let i=${i}+1
	done
}

######启动######
# $1 instance id
start_instance () {
		$vultr_cli instance start "$1"
}

######关机######
# $1 instance id
stop_instance () {
	$vultr_cli instance stop "$1"
}

######重启######
# $1 instance id
restart_instance () {
	$vultr_cli instance restart "$1"
}

######重装系统######
# $1 instance id
reinstall_instance () {
	$vultr_cli instance reinstall "$1"
}

######更换系统######
# $1 instance id
# $2 os
changeos_instance () {
	$vultr_cli instance os change $1 -o $2
}

######启动######
# $1 instance id
# $2 plan
upgrade_instance () {
	$vultr_cli instance plan upgrade "$1" -p "$2"
}

######删除######
# $1 instance id
delete_instance () {
	$vultr_cli instance delete "$1"
}

######创建######
# $1 chosen_area
# $2 chosen_plan
# $3 chosen_os
# $4 chosen_sshkey
# $5 script_id
create_instance() {
	[ -n $5] \
	&& $vultr_cli instance create --region "$1" --plan "$2" --os "$3" --script-id "$5" \
	|| $vultr_cli instance create --region "$1" --plan "$2" --os "$3" --ssh-keys "$4"
}

choise_vultr_sshkey () {
	local sshkey_list=`$vultr_cli ssh list | sed 's/$/,/' | tr -s "\t" | tr -d "\n"`
	local sshkey_total=`echo $sshkey_list | awk 'BEGIN{RS=",",FS="\t"} END{print $1}'`
	if [ -z ${sshkey_total} ]; then
		echo -e "${red}你尚未导入ssh key到Vultr ！${normal}"
		create_vultr_key
		local sshkey_list=`$vultr_cli ssh list | sed 's/$/,/' | tr -s "\t" | tr -d "\n"`
		local sshkey_total=`echo $sshkey_list | awk 'BEGIN{RS=",",FS="\t"} END{print $1}'`
	fi
	local sshkey_name=`echo $sshkey_list | awk 'BEGIN{RS=",",FS="\t"} {print $3}'`
	local sshkey_id=`echo $sshkey_list | awk 'BEGIN{RS=",",FS="\t"} {print $1}'`
	if [ "$sshkey_total" == "1" ]; then
			chosen_sshkey=$sshkey_id
	else
		local i="1"
		echo "检测到你在Vultr上有多个sshkey："
		for name in $sshkey_name
		do
			echo -e "${i}、$name\n"
		done
		echo "----------------------"
		echo "请选择你要的sshkey：" sshkey_number
		chosen_sshkey=${sshkey_id[$sshkey_number]}
	fi
}

choise_vultr_plan () {
	local i=0
	plan_id_list=(`cat ~/.vultr-list | sed -n 's/plan://p' | awk 'BEGIN{FS="="} {print $1}'`)
	plan_name_list=("`cat ~/.vultr-list | sed -n 's/plan://p' | awk 'BEGIN{FS="="} {print $2}'`")
	for plan_name in $plan_name_list
	do
		let i=${i}+1
		echo "${i}、${plan_name}"
	done
	echo "----------------------"
	read -p "选择你要的套餐：" plan_number
	invaild_number $plan_number 1 $i && echo "输入无效！" && exit 1
	let plan_number=${plan_number}-1
	chosen_plan=${plan_id_list[${plan_number}]}
	#echo $chosen_plan
}

choise_vultr_os () {
	local i=0
	os_id_list=(`cat ~/.vultr-list | sed -n 's/os://p' | awk 'BEGIN{FS="="} {print $1}'`)
	os_name_list=("`cat ~/.vultr-list | sed -n 's/os://p' | awk 'BEGIN{FS="="} {print $2}'`")
	for os_name in $os_name_list
	do
		let i=${i}+1
		echo "${i}、${os_name//_/ }"
	done
	echo "----------------------"
	read -p "选择你要的操作系统：" os_number
	invaild_number $os_number 1 $i && echo "输入无效！" && exit 1
	let os_number=${os_number}-1
	chosen_os=${os_id_list[${os_number}]}
	#echo $chosen_os
}

choise_vultr_area () {
	local i=0
	area_id_list=(`cat ~/.vultr-list | sed -n 's/area://p' | awk 'BEGIN{FS="="} {print $1}'`)
	area_name_list=("`cat ~/.vultr-list | sed -n 's/area://p' | awk 'BEGIN{FS="="} {print $2}'`")
	for area_name in $area_name_list
	do
		let i=${i}+1
		echo "${i}、${area_name}"
	done
	echo "----------------------"
	read -p "选择你要的地区：" area_number
	invaild_number $area_number 1 $i && echo "输入无效！" && exit 1
	let area_number=${area_number}-1
	chosen_area=${area_id_list[${area_number}]}
	#echo $chosen_area
}

is_no () {
	[[ $1 != "Y" || $1 != "y" || -z $1 ]] && return 0 || return 1
}

# $1 number
# $2 start nu
# $3 end nu
invaild_number () {
	[ -n "$1" ] && [ `echo $1 | egrep '^[0-9][0-9]*$'` ] && [ $1 -ge $2 ] && [ $1 -le $3 ] \
	&& return 1 || return 0
}

# 必要的准备工作
install_vultr-cli
import_api-key

clear

while [ 1 ]
do
echo "\n 1、开机"
echo " 2、关机"
echo " 3、重启"
echo " 4、创建"
echo " 5、查看列表"
echo " 6、升级套餐"
echo " 7、重装系统"
echo " 8、更换系统"
echo -e "\n 9、重装 Vultr CLI"
echo " 10、重新导入 API KEY"
echo " 11、重新生成 SSH KEY"
echo " ---------------"
echo " 12、退出脚本"
echo " ---------------"
read -p "选择你要的操作：" operate_number
invaild_number $operate_number 1 12 && echo -e "${red}输入有误！${normal}" && exit 1

case $operate_number in
	1)
	echo "===========列出你的VPS============="
	list_vultr_instance
	echo -e "\n0、取消[C]"
	echo "----------------------"
	read -p "选择你要操作的VPS：" id_number
	[ $id_number == "c" -o $id_number == "C" -o $id_number == "0" ] && continue
	invaild_number $id_number 1 ${#instance_id_list[@]} && echo -e "${red}输入有误！${normal}" && exit 1
	instance_id=${instance_id_list[$id_number]}
	start_instance $instance_id
	;;
	2)
	echo "===========列出你的VPS============="
	list_vultr_instance
	echo -e "\n0、取消[C]"
	echo "----------------------"
	read -p "选择你要操作的VPS：" id_number
	[ $id_number == "c" -o $id_number == "C" -o $id_number == "0" ] && continue
	invaild_number $id_number 1 ${#instance_id_list[@]} && echo -e "${red}输入有误！${normal}" && exit 1
	instance_id=${instance_id_list[$id_number]}
	stop_instance $instance_id
	;;
	3)
	echo "===========列出你的VPS============="
	list_vultr_instance
	echo -e "\n0、取消[C]"
	echo "----------------------"
	read -p "选择你要操作的VPS：" id_number
	[ $id_number == "c" -o $id_number == "C" -o $id_number == "0" ] && continue
	invaild_number $id_number 1 ${#instance_id_list[@]} && echo -e "${red}输入有误！${normal}" && exit 1
	instance_id=${instance_id_list[$id_number]}
	restart_instance $instance_id
	;;
	4)
	read -p "你要创建几台VPS：" instance_count
	choise_vultr_os
	choise_vultr_area
	choise_vultr_plan
	echo "1、sshkey登陆"
	echo "2、password登陆"
	read -p "请选择以什么方式登陆：" is_sshkey
	invaild_number $is_sshkey 1 2 && echo -e "${red}输入无效！${normal}" && exit 1
	case $is_sshkey in
		1)
		choise_vultr_sshkey
		create_instance $chosen_area $chosen_plan $chosen_os $chosen_sshkey
		;;
		2)
		#read -p "请设置开机密码，留空则随机：" start_password
		key='0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ.*?^~#$&()<>+-{}[];'
		for i in {1..10}
		do
		index=$[RANDOM%num]
		start_password=$start_password${key:$index:1}
		done
		echo "你的开机密码：${red}$start_password${normal}"
		start_password_base64=`echo "root:$start_password | chpasswd root" | base64`
		script_id=`$vultr_cli script create -n setpasswd -s $start_password_base64 -t boot | awk 'BEGIN{FS="\t"} {if(NR==2) print $1}'`
		#echo $script_id
		for count in `seq 1 $instance_count`
		do
			create_instance $chosen_area $chosen_plan $chosen_os $chosen_sshkey $script_id > /dev/null
		done
		$vultr_cli script delete $script_id > /dev/null
		echo "${green}创建成功！等待启动...${normal}"
		;;
		*)
		;;
	esac
	;;
	5)
	clear
	echo "===========列出你的VPS============="
	list_vultr_instance
	echo -e "\n0、取消[C]"
	echo "-------------------------------------"
	read -p "选择你要操作的VPS：" id_number
	[ $id_number == "c" -o $id_number == "C" -o $id_number == "0" ] && continue
	invaild_number $id_number 1 ${#instance_id_list[@]} && echo -e "${red}输入有误！${normal}" && exit 1
	instance_id=${instance_id_list[$id_number]}
	echo " 1、开机"
	echo " 2、关机"
	echo " 3、重启"
	echo " 4、升级套餐"
	echo " 5、重装系统"
	echo " 6、更换系统"
	echo -e "\n0、返回上一级[C]"
	read -p "选择你要的操作：" choise_number
	[ $id_number == "c" -o $id_number == "C" -o $id_number == "0" ] && continue
	invaild_number $choise_number 1 6 && echo -e "${red}输入无效！${normal}" && continue
	case $choise_number in
		1) start_instance $instance_id
		;;
		2) stop_instance $instance_id
		;;
		3) restart_instance $instance_id
		;;
		4) choise_vultr_plan && upgrade_instance $instance_id $chosen_plan
		;;
		5) reinstall_instance $instance_id
		;;
		6) choise_vultr_os && changeos_instance $instance_id $chosen_os
		;;
		*) echo -e "${red}你输入的有误，请重新输入。${normal}"
		;;
	esac
	;;
	6)
	echo "===========列出你的VPS============="
	list_vultr_instance
	echo -e "\n0、取消[C]"
	echo "----------------------"
	read -p "选择你要操作的VPS：" id_number
	[ $id_number == "c" -o $id_number == "C" -o $id_number == "0" ] && continue
	invaild_number $id_number 1 ${#instance_id_list[@]} && echo -e "${red}输入有误！${normal}" && exit 1
	instance_id=${instance_id_list[$id_number]}
	choise_vultr_plan && upgrade_instance $instance_id $chosen_plan
	;;
	7)
	echo "===========列出你的VPS============="
	list_vultr_instance
	echo -e "\n0、取消[C]"
	echo "----------------------"
	read -p "选择你要操作的VPS：" id_number
	[ $id_number == "c" -o $id_number == "C" -o $id_number == "0" ] && continue
	invaild_number $id_number 1 ${#instance_id_list[@]} && echo -e "${red}输入有误！${normal}" && exit 1
	instance_id=${instance_id_list[$id_number]}
	reinstall_instance $instance_id
	;;
	8)
	echo "===========列出你的VPS============="
	list_vultr_instance
	echo -e "\n0、取消[C]"
	echo "----------------------"
	read -p "选择你要操作的VPS：" id_number
	[ $id_number == "c" -o $id_number == "C" -o $id_number == "0" ] && continue
	invaild_number $id_number 1 ${#instance_id_list[@]} && echo -e "${red}输入有误！${normal}" && exit 1
	instance_id=${instance_id_list[$id_number]}
	choise_vultr_os && changeos_instance $instance_id $chosen_os
	;;
	9) install_vultr-cli "reinstall"
	;;
	10) import_api-key "reimport"
	;;
	11) create_vultr_key
	;;
	12) exit 0
	;;
	*) echo "你输入的有误，请重新输入。"
	;;
esac

done
