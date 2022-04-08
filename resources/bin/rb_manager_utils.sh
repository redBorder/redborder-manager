#!/bin/bash
source /etc/profile
source $RBLIB/rb_manager_functions.sh
RB_PLUGINS_PATH=/var/www/plugins

function usage() {
cat <<EOF
Usage: rb_manager_plugins [-i] [-e] [-c] [-h] [-n node] [-s script] [-p path]
    -i [-n]        Install plugins scripts in the given node
    -e [-n && -s]  Execute a script into a node
    -c [-n && -p]  Copy files to nodes
    -s <script>    The script that is going to be executed.
    -n <node>      The node where is going to be applied the given option
    -p <path>      File/folder Path to be copied
    -h             Print this help

EOF
}

function install(){
  local node=$1
  echo "Installing plugins in $node"
  copy_files $node $RB_PLUGINS_PATH
  # Change ownership
  execute $node "chown -R webui:webui $RB_PLUGINS_PATH"
  # Execution permissions
  execute $node "chmod -R +x $RB_PLUGINS_PATH/plugins/extensions/*"
}

execute_flag=0
install_flag=0
copy_flag=0

while getopts "iecn:s:p:h" opt; do
  case $opt in
    i) install_flag=1
        ;;
    e) execute_flag=1
        ;;
    c) copy_flag=1
        ;;
    n) NODE=$OPTARG ;;
    s) SCRIPT=$OPTARG ;;
    p) PATH=$OPTARG ;;
    h) usage
       exit 0
        ;;
    *) usage
       exit 1
        ;;
  esac
done

IFS=$'\n\t'
if [ $execute_flag -eq 1 ]; then
  if [ "x$NODE" == "x" ] || [ "x$SCRIPT" == "x" ]; then
    echo "Node [-n] and Script [-s] parameters are needed"
  else
    if [ $NODE == "all" ]; then
      executeToAll $SCRIPT
    else
      execute $NODE $SCRIPT
    fi
  fi
elif [ $install_flag -eq 1 ]; then
  if [ "x$NODE" == "x" ]; then
    echo "Node [-n] parameter is needed"
  else
    install $NODE
  fi
elif [ $copy_flag -eq 1 ]; then
  if [ "x$NODE" == "x" ] || [ "x$PATH" == "x" ]; then
    echo "Node [-n] and Script [-p] parameters are needed"
  else
    copy_files $NODE $PATH
  fi
else
  usage
fi
