#!/bin/bash
red="\033[0;31m"
green="\033[0;32m"
yellow="\033[0;33m"
normal="\033[0m"
expired_passwd=3600
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
		echo -e "${yellow}开始安装 Vultr-CLI...${normal}"
		curl -L "https://hub.fastgit.org/vultr/vultr-cli/releases/download/v${version}/vultr-cli_${version}_${os}_${arch}-bit.tar.gz" \
		| tar -zxC /usr/local/bin/
		[ -x ${vultr_cli} ] && clear && echo -e "${yellow}Vultr-CLI 安装成功！${normal}"
	fi
	[ -f ~/.vultr-list ] || curl -sL "https://cdn.jsdelivr.net/gh/looing/vultr-cli@master/.vultr-list" -o ~/.vultr-list
}

import_api-key () {
	local flag=0
	local current_api_key=`sed -r 's/api-key:[[:blank:]]*//' ~/.vultr-cli.yaml`
	current_api_key=${current_api_key:-0}
	[ -f ~/.vultr-cli.yaml ] && flag=1 || touch ~/.vultr-cli.yaml
	[ "${current_api_key}" == "0" ] && flag=0
	[ "$1" == "reimport" ] && flag=0
	if [ ${flag} -eq 0 ]; then
		echo -e "检测到你尚未设置 API KEY，请先设置。"
		[ "${current_api_key}" != "0" ] || echo -e "如有必要可保存当前API KEY: ${yellow}${current_api_key}${normal}"
		read -p "请输入你的Vultr API KEY：" api_key
		[ -z $api_key ] && echo -e "${red}输入的 API KEY 有误！${normal}" && exit 1
		echo "api-key: $api_key" > ~/.vultr-cli.yaml
		echo -e "正在验证你的API KEY，请稍后...\n"
		$vultr_cli instance list > /dev/null
		if [ "$?" == "0" ]; then
			echo -e "${green}验证成功，你输入的 API KEY 有效！${normal}\n"
			read -p "按 [ENTER] 键开始脚本"
		else
			ip=$(curl -s "ip.sb")
			echo "验证失败！请确保你的 API KEY 正确，并已将当前ip地址（$ip）加入到 Vultr 白名单内。" && exit 1
		fi
	fi
}

create_vultr_key () {
	[ -f ~/.ssh/id_rsa_vultr ] && mv ~/.ssh/id_rsa_vultr ./id_rsa_vultr.bak \
	&& echo "----------------------" && echo -e "已将上次的密钥保存在当前目录下 ${red}id_rsa_vultr.bak${normal} 中，注意保存。"
	echo -e "${green}开始创建ssh key...${normal}"
	echo -e ~/.ssh/id_rsa_vultr | ssh-keygen -t rsa -f ~/.ssh/id_rsa_vultr > /dev/null
	echo -e "${green}开始导入ssh key到Vultr...${normal}"
	sshkey_name=ssh-cli-`TZ=UTC-8 date +%Y%m%d%H%M%S`
	$vultr_cli ssh create --name  --key "`cat ~/.ssh/id_rsa_vultr.pub`" > /dev/null
	echo -e "${green}导入成功。Vultr的SSH公钥位于：${normal}${red}~/.ssh/id_rsa_vultr${normal}"
}

list_vultr_instance () {
	local i=1
	instance_list=`$vultr_cli instance list | egrep -v '(ID|=|TOTAL)' | sed '$d' | awk '{print $1}'`
	for instance in $instance_list
	do
		local instance_info=(`$vultr_cli instance get $instance | egrep -i '(^osid|^ram|^disk|^vcpu|^power status|^date created|^main ip|^plan|^region|^id)' \
		| sort | tr -s "\t" | awk 'BEGIN{FS="\t"} {print $2}'`)
		# 1 create date;
		# 2 disk;
		# 3 id
		# 4 ipv4;
		# 5 osid;
		# 6 plan;
		# 7 power status;
		# 8 ram;
		# 9 region;
		# 10 cpu;
		#local create_time=`echo $instance_info | awk 'BEGIN{FS=","} {print $1}'`
		#local disk=`echo $instance_info | awk 'BEGIN{FS=","} {print $2}'`
		local instance_id=${instance_info[2]}
		local ipv4=${instance_info[3]}
		local osid=${instance_info[4]}
		local plan=${instance_info[5]}
		#local ram=`echo "${instance_info}" | awk '{print $7}'`
		local region=${instance_info[8]}
		local power_status=${instance_info[6]}
		#local cpu=`echo "${instance_info}" | awk '{print $12}'`
		region=`cat ~/.vultr-list | sed -n "s/area:${region}=//p"`
		plan=`cat ~/.vultr-list | sed -n "s/plan:${plan}=//p"`
		os=`cat ~/.vultr-list | sed -n "s/os:${osid}=//p"`
		echo -e ${i}、${yellow}地区：${normal}"${region}" ${yellow}ip地址：${normal}"${ipv4}" ${yellow}系统：${normal}"${os}" ${yellow}套餐：${normal}"${plan}"
		instance_id_list[$i]=${instance_id}
		let i=${i}+1
	done
}

######启动######
# $1 instance id
start_instance () {
		local result=`$vultr_cli instance start "$1"`
		[ "${result}" == "Started up instance" ] \
		&& echo -e "${green}开机成功！${normal}\n" \
		|| echo -e "${red}开机失败！${normal} ${result}\n"
}

######关机######
# $1 instance id
stop_instance () {
	local result=`$vultr_cli instance stop "$1"`
	[ "${result}" == "Stopped the instance" ] \
	&& echo -e "${green}关机成功！${normal}\n" \
	|| echo -e "${red}关机失败！${normal} ${result}\n"
}

######重启######
# $1 instance id
restart_instance () {
	local result=`$vultr_cli instance restart "$1"`
	[ "${result}" == "Rebooted instance" ] \
	&& echo -e "${green}重启成功！${normal}\n" \
	|| echo -e "${red}重启失败！${normal} ${result}\n"
}

######重装系统######
# $1 instance id
reinstall_instance () {
	local result=`$vultr_cli instance reinstall "$1"`
	[ "${result}" == "Reinstalled instance" ] \
	&& echo -e "${green}重装成功！${normal}\n" \
	|| echo -e "${red}重装失败！${normal} ${result}\n"
}

######更换系统######
# $1 instance id
# $2 os
changeos_instance () {
	echo -e "${green}正在更换，请稍后...${normal}"
	local result=`$vultr_cli instance os change $1 -o $2`
	[ "${result}" == "Updated OS" ] \
	&& echo -e "${green}系统更换成功！${normal}\n" \
	|| echo -e "${red}系统更换失败！${normal} ${result}\n"
}

######升级######
# $1 instance id
# $2 plan
upgrade_instance () {
	local result=`$vultr_cli instance plan upgrade "$1" -p "$2"`
	[ "${result}" == "Upgraded plan" ] \
	&& echo -e "${green}升级成功！${normal}\n" \
	|| echo -e "${red}升级失败！${normal} ${result}\n"
}

######删除######
# $1 instance id
delete_instance () {
	local result=`$vultr_cli instance delete "$1"`
	[ "${result}" == "Deleted instance" ] \
	&& echo -e "${green}删除成功！${normal}\n" \
	|| echo -e "${red}删除失败！${normal} ${result}\n"
}

######创建######
# $1 chosen_area
# $2 chosen_plan
# $3 chosen_os
# $4 chosen_sshkey
# $5 script_id
create_instance() {
	[ -n $5 ] \
	&& local result=`$vultr_cli instance create --region "$1" --plan "$2" --os "$3" --script-id "$5"` \
	|| local result=`$vultr_cli instance create --region "$1" --plan "$2" --os "$3" --ssh-keys "$4"`
	echo ${result} | grep -qi "instance info" \
	&& echo -e "\n${green}创建成功！${normal}\n1、密码登陆可能需要等待1分钟的时间，否则会显示密码错误。\n2、当前创建的VPS的IP地址请前往【主菜单】-【查看列表】查看\n" \
	|| echo -e "${red}创建失败！${normal}\n${result}\n"
}

choise_vultr_sshkey () {
	local sshkey_list=`$vultr_cli ssh list`
	local sshkey_total=`echo "${sshkey_list}" | awk 'END{print $1}'`
	if [ -z ${sshkey_total} ]; then
		echo -e "${red}你尚未导入ssh key到Vultr ！${normal}"
		create_vultr_key
		local sshkey_list=`$vultr_cli ssh list`
		local sshkey_total=`echo "${sshkey_list}" | awk 'END{print $1}'`
	fi
	local sshkey_list=`echo "${sshkey_list}" | awk '{if(NR!=1 && NR<='''${sshkey_total}'''+1) print $0}'`
	local sshkey_name=(`echo "${sshkey_list}" | awk '{print $3}'`)
	#local sshkey_date_created=(`echo "${sshkey_list}" | awk '{print $2}'`)
	local sshkey_id=(`echo "${sshkey_list}" | awk '{print $1}'`)
	if [ "$sshkey_total" == "1" ]; then
			chosen_sshkey=$sshkey_id
	else
		echo "检测到你在Vultr上有多个sshkey："
		for((i=0;i<sshkey_total;i++))
		do
			echo -e "${i}、${sshkey_name[$i]}"
		done
		echo "----------------------"
		read -p "请选择你要的sshkey：" sshkey_number
		chosen_sshkey=${sshkey_id[$sshkey_number-1]}
	fi
	read -p "请自行检查你的本地有 ${sshkey_name[$sshkey_number-1]} 对应的密钥，否则创建即失联。[Y|N] " is_sshkey
	is_no $is_sshkey && exit 0 
}

choise_vultr_plan () {
	plan_id_list=(`cat ~/.vultr-list | sed -n 's/plan://p' | awk 'BEGIN{FS="="} {print $1}'`)
	plan_name_list=(`cat ~/.vultr-list | sed -n 's/plan://p' | awk 'BEGIN{FS="="} {print $2}'`)
	for (( i=0;i<${#plan_name_list[@]};i++ ))
	do
		echo "$((${i}+1))、${plan_name_list[$i]}"
	done
	echo "----------------------"
	read -p "选择你要的套餐：" plan_number
	invaild_number $plan_number 1 $i && echo "输入无效！" && exit 1
	chosen_plan=${plan_id_list[${plan_number}-1]}
	#echo $chosen_plan
}

choise_vultr_os () {
	os_id_list=(`cat ~/.vultr-list | sed -n 's/os://p' | awk 'BEGIN{FS="="} {print $1}'`)
	os_name_list=(`cat ~/.vultr-list | sed -n 's/os://p' | awk 'BEGIN{FS="="} {print $2}'`)
	for (( i=0;i<${#os_name_list[@]};i++ ))
	do
		echo "$((${i}+1))、${os_name_list[$i]}"
	done
	echo "----------------------"
	read -p "选择你要的操作系统：" os_number
	invaild_number $os_number 1 $i && echo "输入无效！" && exit 1
	chosen_os=${os_id_list[${os_number}-1]}
	#echo $chosen_os
}

choise_vultr_area () {
	area_id_list=(`cat ~/.vultr-list | sed -n 's/area://p' | awk 'BEGIN{FS="="} {print $1}'`)
	area_name_list=(`cat ~/.vultr-list | sed -n 's/area://p' | awk 'BEGIN{FS="="} {print $2}'`)
	for (( i=0;i<${#area_name_list[@]};i++ ))
	do
		echo "$((${i}+1))、${area_name_list[$i]}"
	done
	echo "----------------------"
	read -p "选择你要的地区：" area_number
	invaild_number $area_number 1 $i && echo "输入无效！" && exit 1
	chosen_area=${area_id_list[${area_number}-1]}
	#echo $chosen_area
}

is_no () {
	[[ $1 != "Y" && $1 != "y" && ! -z $1 ]] && return 0 || return 1
}

# $1 number
# $2 start nu
# $3 end nu
invaild_number () {
	[ -n "$1" ] && [ `echo $1 | egrep '^[0-9][0-9]*$'` ] && [ $1 -ge $2 ] && [ $1 -le $3 ] \
	&& return 1 || return 0
}

remove_expired_passwd_script () {
        which ntpdate > /dev/null || apt install ntpdate -y > /dev/null || yum install ntpdate -y > /dev/null &
        ntpdate -u time.windows.com > /dev/null &
        local scripts_list=`$vultr_cli script list | tail -n +2 | head -n -3`
        local script_id=(`echo "${scripts_list}" | awk '{print $1}'`)
        local script_date_modified=(`echo "${scripts_list}" | awk '{print $3}'`)
        local script_name=(`echo "${scripts_list}" | awk '{print $5}'`)
        for((i=0;i<${#script_name[@]};i++))
        do
                if [ "${script_name[$i]}"=="setpasswd" ]; then
                        local time_diff=$((`date +%s` - `date +%s -d ${script_date_modified[$i]}`))
                        if [ $time_diff -gt $expired_passwd ]; then
                                $vultr_cli script delete ${script_id[$i]} > /dev/null &
                        fi
                fi
        done
}

# 必要的准备工作
install_vultr-cli
import_api-key
remove_expired_passwd_script


while [ 1 ]
do
clear
echo " 1、开机"
echo " 2、关机"
echo " 3、重启"
echo " 4、创建"
echo " 5、删除"
echo " 6、查看列表"
echo " 7、升级套餐"
echo " 8、重装系统"
echo " 9、更换系统"
echo -e "\n 10、重装 Vultr CLI"
echo " 11、重新导入 API KEY"
echo " 12、重新生成 SSH KEY"
echo " ---------------"
echo " 13、退出脚本"
echo " ---------------"
read -p "选择你要的操作：" operate_number
invaild_number $operate_number 1 14 && echo -e "${red}输入有误！${normal}" && exit 1

case $operate_number in
	1)
	clear
	echo "===========列出你的VPS============="
	list_vultr_instance
	echo -e "\n0、取消[C]"
	echo "----------------------"
	read -p "选择你要开机的VPS：" id_number
	[ $id_number == "c" -o $id_number == "C" -o $id_number == "0" -o -z $id_number ] && continue
	invaild_number $id_number 1 ${#instance_id_list[@]} && echo -e "${red}输入有误！${normal}" && exit 1
	instance_id=${instance_id_list[$id_number]}
	start_instance $instance_id
	read -p "按 [ENTER] 键返回上一级"
	;;
	2)
	clear
	echo "===========列出你的VPS============="
	list_vultr_instance
	echo -e "\n0、取消[C]"
	echo "----------------------"
	read -p "选择你要关机的VPS：" id_number
	[ $id_number == "c" -o $id_number == "C" -o $id_number == "0" -o -z $id_number ] && continue
	invaild_number $id_number 1 ${#instance_id_list[@]} && echo -e "${red}输入有误！${normal}" && exit 1
	instance_id=${instance_id_list[$id_number]}
	stop_instance $instance_id
	read -p "按 [ENTER] 键返回上一级"
	;;
	3)
	clear
	echo "===========列出你的VPS============="
	list_vultr_instance
	echo -e "\n0、取消[C]"
	echo "----------------------"
	read -p "选择你要重启的VPS：" id_number
	[ $id_number == "c" -o $id_number == "C" -o $id_number == "0" -o -z $id_number ] && continue
	invaild_number $id_number 1 ${#instance_id_list[@]} && echo -e "${red}输入有误！${normal}" && exit 1
	instance_id=${instance_id_list[$id_number]}
	restart_instance $instance_id
	read -p "按 [ENTER] 键返回上一级"
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
		read -p "按 [ENTER] 键返回上一级"
		;;
		2)
		#read -p "请设置开机密码，留空则随机：" start_password
		key='0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ.*?^~#$&()<>+-{}[];'
		num=${#key}
		for i in {1..10}
		do
		index=$[RANDOM%num]
		start_password=${start_password}${key:$index:1}
		done
		echo -e "你的开机密码：${red}$start_password${normal}"
		start_password_base64=`echo "echo "root:${start_password}" | chpasswd" | base64`
		script_id=`$vultr_cli script create -n setpasswd -s $start_password_base64 -t boot | awk 'BEGIN{FS="\t"} {if(NR==2) print $1}'`
		#echo $script_id
		for count in `seq 1 $instance_count`
		do
			create_instance $chosen_area $chosen_plan $chosen_os 2 $script_id
		done
		#$vultr_cli script delete $script_id
		read -p "按 [ENTER] 键返回上一级"
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
	read -p "选择你要删除的VPS：" id_number
	id_number=($id_number)
	read -p "删除后数据无法恢复！是否确认[Y|N] " is_delete
	is_no ${is_delete} && continue
	for id in ${id_number[@]}
	do
	[ $id == "c" -o $id == "C" -o $id == "0" -o -z $id ] && continue
	invaild_number $id 1 ${#instance_id_list[@]} && echo -e "${red}输入有误！${normal}" && exit 1
	instance_id=${instance_id_list[$id]}
	echo $instance_id
	delete_instance $instance_id
	done
	read -p "按 [ENTER] 键返回上一级"
	;;
	6)
	clear
	echo "===========列出你的VPS============="
	list_vultr_instance
	echo -e "\n0、取消[C]"
	echo "-------------------------------------"
	read -p "按 [ENTER] 键返回上一级："
	;;
	7)
	clear
	echo "===========列出你的VPS============="
	list_vultr_instance
	echo -e "\n0、取消[C]"
	echo "----------------------"
	read -p "选择你要升级的VPS：" id_number
	[ $id_number == "c" -o $id_number == "C" -o $id_number == "0" -o -z $id_number ] && continue
	invaild_number $id_number 1 ${#instance_id_list[@]} && echo -e "${red}输入有误！${normal}" && exit 1
	instance_id=${instance_id_list[$id_number]}
	choise_vultr_plan && upgrade_instance $instance_id $chosen_plan
	read -p "按 [ENTER] 键返回上一级"
	;;
	8)
	clear
	echo "===========列出你的VPS============="
	list_vultr_instance
	echo -e "\n0、取消[C]"
	echo "----------------------"
	read -p "选择你要重装的VPS：" id_number
	[ $id_number == "c" -o $id_number == "C" -o $id_number == "0" -o -z $id_number ] && continue
	invaild_number $id_number 1 ${#instance_id_list[@]} && echo -e "${red}输入有误！${normal}" && exit 1
	instance_id=${instance_id_list[$id_number]}
	echo -e "重装系统后数据无法恢复！是否确认[Y|N] " is_reinstall
	is_no $is_reinstall || reinstall_instance $instance_id
	read -p "按 [ENTER] 键返回上一级"
	;;
	9)
	clear
	echo "===========列出你的VPS============="
	list_vultr_instance
	echo -e "\n0、取消[C]"
	echo "----------------------"
	read -p "选择你要更换系统的VPS编号：" id_number
	[ $id_number == "c" -o $id_number == "C" -o $id_number == "0" -o -z $id_number ] && continue
	invaild_number $id_number 1 ${#instance_id_list[@]} && echo -e "${red}输入有误！${normal}" && exit 1
	instance_id=${instance_id_list[$id_number]}
	read -e "更换系统后数据无法恢复！是否确认[Y|N]${normal} " is_changeos
	is_no $is_changeos || echo -e "选择你要更换的操作系统：\n----------------------" && choise_vultr_os && changeos_instance $instance_id $chosen_os
	read -p "按 [ENTER] 键返回上一级"
	;;
	10) install_vultr-cli "reinstall"
	;;
	11) import_api-key "reimport"
	;;
	12) create_vultr_key
	;;
	13) exit 0
	;;
	14) choise_vultr_os
	;;
	*) echo "你输入的有误，请重新输入。"
	;;
esac

done

