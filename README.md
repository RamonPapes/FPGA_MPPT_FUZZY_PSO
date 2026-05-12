# Hybrid PSO-Fuzzy MPPT em VHDL

Este projeto implementa um controlador MPPT híbrido para sistemas fotovoltaicos, combinando lógica fuzzy e Particle Swarm Optimization (PSO) em VHDL.[1] Desenvolvido no Quartus Lite.

## Arquivos principais

- `hybrid_mppt_pkg.vhd`: pacote com constantes, tipos, funções auxiliares, funções fuzzy e lógica de suporte ao PSO.
- `hybrid_pso_fuzzy_mppt.vhd`: módulo principal do controlador híbrido PSO-Fuzzy MPPT.
- `tb_hybrid_pso_fuzzy_export.vhd`: testbench para simulação e exportação dos resultados.
- `dataset_scaled.txt`: arquivo de entrada contendo valores escalados de tensão e corrente.
- `resultados_hybrid.txt`: arquivo gerado pela simulação com os resultados do controlador.

## Referência

[1] PATNAIK, Bhabani; SWAIN, Sarat Chandra; DASH, Ritesh; BALLAJI, Adithya. Design and analysis of MPPT using advanced PSO based on fuzzy Fokker-Planck solution under partial shading condition. In: INTERNATIONAL CONFERENCE ON SMART GENERATION COMPUTING, COMMUNICATION AND NETWORKING (SMART GENCON), 2022, Karnataka. Proceedings [...]. Piscataway: IEEE, 2022. p. 1-6. DOI: 10.1109/SMARTGENCON56628.2022.10083568.