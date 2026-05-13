# Hybrid PSO-Fuzzy MPPT em VHDL

Este projeto implementa um controlador MPPT híbrido para sistemas fotovoltaicos, combinando lógica fuzzy e Particle Swarm Optimization (PSO) em VHDL.

O relatorio sobre os eperiumentos pode ser vistoa qui 
https://pt.overleaf.com/read/cqjckrcscbzw#d27700

[1] Desenvolvido no Quartus Lite.

## Arquivos VHDL principais

- `hybrid_mppt_pkg.vhd`: pacote com constantes, tipos, funções auxiliares, funções fuzzy e lógica de suporte ao PSO.
- `mppt_measurement_unit.vhd`: módulo responsável pelo cálculo da potência, variação de potência, variação de tensão, erro e variação do erro.
- `mppt_fuzzy_ffp_unit.vhd`: módulo responsável pela lógica fuzzy, pelo cálculo do passo Fokker--Planck e pelo refinamento do duty cycle.
- `pso_particle_update_unit.vhd`: módulo responsável pela atualização das partículas do PSO, incluindo posição, velocidade, `pbest` e `gbest`.
- `hybrid_pso_fuzzy_mppt.vhd`: módulo principal do controlador híbrido PSO--Fuzzy MPPT, responsável por instanciar e conectar os blocos internos.
- `tb_hybrid_pso_fuzzy_export.vhd`: testbench utilizado para simulação, leitura dos dados pré-processados e exportação dos resultados.

## Reprodução dos experimentos

A reprodução dos experimentos é feita em duas etapas: primeiro, realiza-se a busca exploratória dos hiperparâmetros; depois, executa-se a simulação final com os melhores valores encontrados.

Para buscar os hiperparâmetros, execute:

```powershell 
    python .\optimize_hyperparameters.py
```

Para rodar os experimentos finais, execute:
```powershell
    .\run_experiment.ps1 -CleanWork
```

O script ```run_experiment.ps1``` realiza o pré-processamento dos dados, compila os arquivos VHDL, executa o testbench e gera os arquivos de resultado na pasta ```results/```.

## Referência

[1] PATNAIK, Bhabani; SWAIN, Sarat Chandra; DASH, Ritesh; BALLAJI, Adithya. Design and analysis of MPPT using advanced PSO based on fuzzy Fokker-Planck solution under partial shading condition. In: INTERNATIONAL CONFERENCE ON SMART GENERATION COMPUTING, COMMUNICATION AND NETWORKING (SMART GENCON), 2022, Karnataka. Proceedings [...]. Piscataway: IEEE, 2022. p. 1-6. DOI: 10.1109/SMARTGENCON56628.2022.10083568.