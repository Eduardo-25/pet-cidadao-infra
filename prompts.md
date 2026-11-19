# Prompts utilizados — Pet Cidadão (Operating Systems)

Registro dos prompts utilizados como apoio na implementação da infraestrutura Linux do Pet Cidadão. Os textos foram consolidados para documentação e representam o conteúdo das solicitações, não transcrições literais.

## Prompts

### Prompt 1 — Acesso remoto por SSH

**Prompt (consolidado):** Oriente a instalação e habilitação do SSH no CT-NODE e o acesso a partir do CT-CLIENT usando a conta nominal do executor. Inclua os testes do serviço, da porta 22 e da identidade da sessão remota.

**Finalidade:** permitir acesso remoto ao nó principal e comprovar a comunicação entre as VMs.

**Verificação prática:** o serviço `ssh` foi habilitado no CT-NODE. O login a partir do CT-CLIENT foi realizado com `EduardoLima_RM554804`; na sessão remota foram conferidos `hostname`, `whoami` e `id`.

### Prompt 2 — Configuração de DNS com BIND9

**Prompt (consolidado):** Ajude a configurar o BIND9 para o domínio de teste `petcidadao.test`, usando `192.168.56.10` como servidor DNS. Revise os arquivos de opções, declaração da zona e registros A; explique como validar a configuração e testar consultas pelo CT-CLIENT.

**Finalidade:** disponibilizar nomes consistentes para os componentes do projeto.

**Verificação prática:** `named-checkzone` e `named-checkconf -z` validaram a zona `petcidadao.test`. O serviço `named` ficou ativo e as consultas DNS para os registros do projeto foram testadas a partir do cliente, direcionadas a `192.168.56.10`.

### Prompt 3 — Monitoramento de CPU, memória e disco

**Prompt (consolidado):** Ajude a implementar um script Bash que monitore CPU, memória e uso de disco, registre data, equipe, usuário, hostname, valores e alertas, e execute continuamente como serviço systemd com reinicialização automática.

**Finalidade:** acompanhar os recursos do nó e registrar condições normais ou situações que exijam atenção.

**Verificação prática:** `monitor.log` e `journalctl -u citizentech-monitor` apresentaram amostras periódicas de CPU, memória e disco, com estado e alertas. Os registros observados incluíram valores como CPU 5,1%, memória 44,4% e disco 1%, com `status=OK` e `alertas=Nenhum`. O disparo de alertas por ultrapassagem dos limites deve ser demonstrado no teste específico de limiar.

### Prompt 4 — Hospedagem da API Pet Cidadão

**Prompt (consolidado):** Analise o backend ASP.NET Core e oriente a preparação do CT-NODE para instalar dependências, configurar o SQL Server, criar a base, aplicar migrations, executar testes, publicar a API e configurá-la como serviço systemd. Mantenha credenciais fora do repositório e disponibilize a API na porta 5080 somente para o CT-CLIENT.

**Finalidade:** hospedar a aplicação desenvolvida em outra disciplina e executar seus componentes na infraestrutura Linux.

**Verificação prática:** o SDK .NET e o SQL Server foram instalados; a base `PetCidadaoDB` recebeu as migrations; os testes automatizados passaram (21 aprovados); e a API foi publicada em `/opt/petcidadao/publish` e executada por `petcidadao-api.service`. O endpoint `/api/Usuario` retornou HTTP 200. A connection string ficou em `/etc/petcidadao/petcidadao.env`, fora do repositório e com permissões restritas.

### Prompt 5 — Provisionamento automatizado da aplicação

**Prompt (consolidado):** Ajude a criar e revisar um script Bash repetível para provisionar a aplicação. Ele deve validar o ambiente, instalar dependências ausentes, verificar SQL Server e arquivo de ambiente protegido, obter o código, restaurar, testar, aplicar migrations, publicar a API, instalar a unit systemd, configurar o firewall, testar um endpoint e registrar as etapas em log sem expor credenciais.

**Finalidade:** automatizar a instalação e publicação da API, reduzindo etapas manuais.

**Verificação prática:** `bash -n` validou a sintaxe. A execução de `provisiona-aplicacao.sh` foi registrada em `provisiona-aplicacao.log`, incluindo 21 testes aprovados, migrations atualizadas, publicação concluída, serviço ativo e resposta HTTP 200 de `/api/Usuario`.

### Prompt 6 — Provisionamento automatizado da infraestrutura e DNS

**Prompt (consolidado):** Ajude a criar e revisar um script Bash para provisionar o CT-NODE, preservando a rota padrão pela NAT. O script deve validar hostname e IP privado, verificar dependências, instalar configurações do BIND9 com backup, validar a zona antes de reiniciar o serviço, habilitar SSH e DNS, configurar o UFW para permitir o CT-CLIENT e registrar as operações em log.

**Finalidade:** automatizar a configuração do nó principal. A configuração DNS foi incorporada a `provisiona-infraestrutura.sh`, portanto não há um script DNS separado.

**Verificação prática:** `bash -n` validou a sintaxe. Na execução de 19/11/2026, o script confirmou hostname `ct-node-rm558418`, IP `192.168.56.10/24`, rota padrão pela NAT `enp0s3`, zona `petcidadao.test` validada, serviços BIND9 e SSH ativos e regras UFW para as portas 22, 53 e 5080 a partir de `192.168.56.20`. A consulta de `api.petcidadao.test` retornou `192.168.56.10`, e o log registrou a conclusão com sucesso.
