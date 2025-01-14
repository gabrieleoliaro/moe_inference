#!/bin/bash
set -e

shopt -s expand_aliases
alias python=python3

rm -rf data && mkdir data && cd data

# Download dataset
wget https://s3.amazonaws.com/research.metamind.io/wikitext/wikitext-103-raw-v1.zip
unzip wikitext-103-raw-v1.zip
rm wikitext-103-raw-v1.zip

# Encode it with GPT-2 BPE
mkdir -p gpt2_bpe
wget -O gpt2_bpe/encoder.json https://dl.fbaipublicfiles.com/fairseq/gpt2_bpe/encoder.json
wget -O gpt2_bpe/vocab.bpe https://dl.fbaipublicfiles.com/fairseq/gpt2_bpe/vocab.bpe
for SPLIT in train valid test; do \
    python -m examples.roberta.multiprocessing_bpe_encoder \
        --encoder-json gpt2_bpe/encoder.json \
        --vocab-bpe gpt2_bpe/vocab.bpe \
        --inputs wikitext-103-raw/wiki.${SPLIT}.raw \
        --outputs wikitext-103-raw/wiki.${SPLIT}.bpe \
        --keep-empty \
        --workers 60; \
done

# Preprocess / binarize the data using GPT-2 fairseq dictionary
wget -O gpt2_bpe/dict.txt https://dl.fbaipublicfiles.com/fairseq/gpt2_bpe/dict.txt
fairseq-preprocess \
    --only-source \
    --srcdict gpt2_bpe/dict.txt \
    --trainpref wikitext-103-raw/wiki.train.bpe \
    --validpref wikitext-103-raw/wiki.valid.bpe \
    --testpref wikitext-103-raw/wiki.test.bpe \
    --destdir data-bin/wikitext-103 \
    --workers 60

# Download pre-trained 15b MoE checkpoint
wget https://dl.fbaipublicfiles.com/fairseq/models/lm/en_moe_lm_15b.tar.gz
tar -xf en_moe_lm_15b.tar.gz
rm en_moe_lm_15b.tar.gz

# Truncate model-shared.pt's embedding table to only include the first 50264 entries
python -c "import torch; num_types = 50264; ckpt = torch.load('en_moe_lm_15b/model-shared.pt'); print(ckpt['model']['decoder.embed_tokens.weight'].shape); ckpt['model']['decoder.embed_tokens.weight'] = ckpt['model']['decoder.embed_tokens.weight'][:num_types]; ckpt['model']['decoder.output_projection.weight'] = ckpt['model']['decoder.output_projection.weight'][:num_types]; torch.save(ckpt, 'en_moe_lm_15b/model-shared.pt')"

cd ..
