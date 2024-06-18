--=================================================
   -- Bibliotecas
--=================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

   --=================================================
   -- Entidade
   --=================================================

entity ps2_receptor is
   port (
      clk, reset: in  std_logic;
      ps2_data, ps2_clk: in  std_logic; 
      rx_in_enable: in std_logic;
      rx_out_done: out  std_logic;
      data_out: out std_logic_vector(7 downto 0)
   );
end ps2_receptor;

   --=================================================
   -- Arquitetura
   --=================================================

architecture arch of ps2_receptor is
   type maq_estados is (idle, dps, load);
   signal estado_atual, estado_prox: maq_estados;
   signal filtro_atual, filtro_prox:
          std_logic_vector(7 downto 0);
   signal filtro_clk_atual,filtro_clk_prox: std_logic;
   signal buffer_atual, buffer_prox: std_logic_vector(10 downto 0);
   signal contador_atual,contador_prox: unsigned(3 downto 0);
   signal borda_descida: std_logic;
begin
   --=================================================
   -- Processo de Filtragem e Detecção da Borda de Descida
   --=================================================
   process (clk, reset)
   begin
      if reset='1' then
         filtro_atual <= (others=>'0');
         filtro_clk_atual <= '0';
      elsif rising_edge(clk) then
         filtro_atual <= filtro_prox;
         filtro_clk_atual <= filtro_clk_prox;
      end if;
   end process;

   filtro_prox <= filtro_atual(7 downto 1) & ps2_clk;
   filtro_clk_prox <= '1' when filtro_atual="11111111" else
                  '0' when filtro_atual="00000000" else
                  filtro_clk_atual;
   borda_descida <= filtro_clk_atual and (not filtro_clk_prox);

   --=================================================
   -- Máquina de Estados Finita (FSM) para Extrair Dados
   --=================================================
   -- registradores
   process (clk, reset)
   begin
      if reset='1' then
         estado_atual <= idle;
         contador_atual  <= (others=>'0');
         buffer_atual <= (others=>'0');
      elsif (clk'event and clk='1') then
         estado_atual <= estado_prox;
         contador_atual <= contador_prox;
         buffer_atual <= buffer_prox;
      end if;
   end process;

   -- lógica de prox estado
   process( estado_atual,contador_atual,buffer_atual,borda_descida,rx_in_enable,ps2_data)
   begin
      rx_out_done <='0';
      estado_prox <= estado_atual;
      contador_prox <= contador_atual;
      buffer_prox <= buffer_atual;
      case estado_atual is
         when idle =>
            if borda_descida='1' and rx_in_enable='1' then
               buffer_prox <= ps2_data & buffer_atual(10 downto 1);
               contador_prox <= "1001";
               estado_prox <= dps;
            end if;
         when dps =>  -- 8 data + 1 pairty + 1 stop
            if borda_descida='1' then
            buffer_prox <= ps2_data & buffer_atual(10 downto 1);
               if contador_atual = 0 then
                   estado_prox <=load;
               else
                   contador_prox <= contador_atual - 1;
               end if;
            end if;
         when load =>
            -- 1 extra clock to complete the last shift
            estado_prox <= idle;
            rx_out_done <='1';
      end case;
   end process;
   -- output
   data_out <= buffer_atual(8 downto 1); -- data bits
end arch;
