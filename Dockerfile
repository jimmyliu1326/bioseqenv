# base img
FROM condaforge/mambaforge:4.12.0-0

# install basic dependencies
RUN apt-get update && \
    apt-get install -y curl wget libssl1.0 && \
    rm -rf /var/lib/apt/lists/*

# install seqdb
RUN seqdb_vers="1.0" && \
    wget https://github.com/jimmyliu1326/seqdb/archive/refs/tags/v${seqdb_vers}.tar.gz -O /seqdb.tar.gz && \
    tar -xzf /seqdb.tar.gz && \
    rm /seqdb.tar.gz && \
    ln -s /seqdb-${seqdb_vers}/seqdb /usr/local/bin/seqdb

RUN addgroup --gid 1000 docker && \
    adduser --uid 1000 --ingroup docker --home /home/docker --shell /bin/sh --disabled-password --gecos "" docker

ADD BatchTracy.sh /usr/local/bin/

# add yaml config to /conf
ADD conda/ /conf/

# create a conda env for each yaml config
RUN CONDA_DIR="/opt/conda" && \
    for file in $(ls /conf); do mamba env create --file /conf/$file; mamba clean --all --yes; done

# clean up unused and cached pkgs
RUN CONDA_DIR="/opt/conda" && \
    rm -rf $CONDA_DIR/conda-meta && \
    rm -rf $CONDA_DIR/include && \
    rm -rf $CONDA_DIR/lib/python3.*/site-packages/pip && \
    find $CONDA_DIR -name '__pycache__' -type d -exec rm -rf '{}' '+'