#!/bin/bash
set -e

# OPTS

DEV=0
HELP=0
PREFIX="~"

ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dev) ARGS+=("-d"); shift;;
        --help) ARGS+=("-h"); shift;;
        --prefix)
            if [[ -z "$2" ]]; then
                echo "Erro: Você deve passar algum parâmetro junto com o prefixo!"
                exit 1
            fi
            ARGS+=("-p" "$2")
            shift 2
            ;;
        *)
            ARGS+=("$1")
            shift
            ;;
    esac
done

set -- "${ARGS[@]}"

while getopts "dhp:" opt; do
    case "$opt" in
        d)
            DEV=1
        ;;
        h)
            HELP=1
        ;;
        p)
            PREFIX="${OPTARG%/}"
        ;;
        *)
            echo "Opção Inválida! -h ou --help para ajuda!"
            exit 1
        ;;
    esac
done

set --

if [[ $HELP -eq 1 ]]; then
    echo "./install.sh [OPTIONS]"
    echo "-d --dev -> Executar mostrando avisos e erros"
    echo "-p --prefix -> Escolher lugar para instalar o ambiente Conda"
    exit 0
fi

# STPO

out() {
    if [[ $DEV -eq 1 ]]; then
        "$@"
    else
        "$@" > /dev/null 2>&1
    fi
}

PREFIX="$(realpath -m "${PREFIX/#\~/$HOME}")"

# Visual Colors and Texts
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NOCOLOR='\033[0m'

log_info() {
    echo -e "${YELLOW}[INFO]${NOCOLOR} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NOCOLOR} $1"
    exit 1
}

log_success() {
    echo -e "${GREEN}[OK]${NOCOLOR} $1"
}

# Script

log_info "Verificando instalação do Conda..."

NEW_CONDA=0

if [ -f "$PREFIX/miniconda3/bin/activate" ]; then
    log_success "Conda ja instalado."
else 
    log_info "Instalando Conda..."
    out wget -O ~/miniconda.sh https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
    bash ~/miniconda.sh -b -p "$PREFIX/miniconda3"
    rm ~/miniconda.sh
    log_success "Conda instalado com sucesso"
    NEW_CONDA=1
fi

# Setup Environment
log_info "Ajustando ambiente Conda..."
source "$PREFIX/miniconda3/bin/activate"
if [[ $NEW_CONDA -eq 1 ]]; then
    out conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main
    out conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r
fi
out conda remove -n OpenposeConda --all -y || true
out conda create -n OpenposeConda python=3.10 -y
conda activate OpenposeConda
pip install -q ipykernel
out conda install -c conda-forge boost boost-cpp cmake compilers glog=0.4.0 hdf5 libgl libopengl libprotobuf=3.20.1 make openblas opencv=4.6.0 protobuf=3.20.1 qt -y
log_success "Ambiente Conda configurado com sucesso"

log_info "Construir OpenPose para Placa ${GREEN}NVIDIA${NOCOLOR}? [y/[n]]: "
read GPU_CONFIG

if [[ $GPU_CONFIG == "y" || $GPU_CONFIG == "Y" ]]; then
    GPU_CONFIG="GPU"
    out conda install -c nvidia/label/cuda-11.8.0 cuda-toolkit -y
else
    GPU_CONFIG="CPU_ONLY"
fi

OPENPOSE_EXIST=0

if [ -d "openpose/models" ]; then
    log_info "O diretório OpenPose já existe. Deseja criar um novo? [[y]/n]: "
    read NEW_OPENPOSE

    if [[ $NEW_OPENPOSE == "n" || $NEW_OPENPOSE == "N" ]]; then
        OPENPOSE_EXIST=1
        shopt -s nullglob

        cd openpose/models

        folders=("face" "hand" "pose/body_25" "pose/coco")

        NEW_MODELS=0

        for folder in "${folders[@]}"; do
            files=("$folder"/*.caffemodel)
            if [ ${#files[@]} -lt 1 ]; then
                log_info "Modelos não encontrados. Baixando modelos."
                ./getModels.sh
                log_success "Modelos instalados com sucesso."
                NEW_MODELS=1
                break
            fi
        done

        cd ../..

        if [[ $NEW_MODELS -eq 0 ]]; then
            log_info "Modelos já instalados. Prosseguindo..."
        fi
    fi
fi

if [[ $OPENPOSE_EXIST -eq 0 ]]; then
    log_info "Clonando repositório OpenPose..."
    rm -rf openpose
    git clone -q https://github.com/CMU-Perceptual-Computing-Lab/openpose.git
    log_success "Repositório clonado."
    cd openpose/models
    log_info "Instalando modelos..."
    ./getModels.sh
    log_success "Modelos instalados."
    cd ../..
fi

cd openpose

log_info "Criando Build OpenPose..."

rm -rf build
mkdir build
cd build
export LD_LIBRARY_PATH="$CONDA_PREFIX/lib:$LD_LIBRARY_PATH"
out cmake .. -G  "Unix Makefiles" -D GPU_MODE="$GPU_CONFIG" -D CMAKE_PREFIX_PATH="$CONDA_PREFIX" || log_error "Erro ao fazer o cmake do OpenPose"
# Download Fixed io.cpp and FindAtlas.cmake
out wget -O ../3rdparty/caffe/src/caffe/util/io.cpp https://raw.githubusercontent.com/TheoSoares/fix-openpose/main/io.cpp
out wget -O ../3rdparty/caffe/cmake/Modules/FindAtlas.cmake https://raw.githubusercontent.com/TheoSoares/fix-openpose/main/FindAtlas.cmake

log_info "Make OpenPose..."

out make -j$(nproc) || log_error "Erro ao fazer o make do OpenPose"

log_success "OpenPose instalado com sucesso!"
