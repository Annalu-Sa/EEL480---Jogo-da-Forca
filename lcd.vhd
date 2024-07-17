------------------------------------------------------------------
--  lcd.vhd -- general LCD testing program
------------------------------------------------------------------
--  Author -- Dan Pederson, 2004
--			  -- Barron Barnett, 2004
--			  -- Jacob Beck, 2006
------------------------------------------------------------------
--  This module is a test module for implementing read/write and
--  initialization routines for an LCD on the Digilab boards
------------------------------------------------------------------
--  Revision History:								    
--  05/27/2004(DanP):  created
--  07/01/2004(BarronB): (optimized) and added writeDone as output
--  08/12/2004(BarronB): fixed timing issue on the D2SB
--  12/07/2006(JacobB): Revised code to be implemented on a Nexys Board
--				Changed "Hello from Digilent" to be on one line"
--				Added a Shift Left command so that the message
--				"Hello from Diligent" is shifted left by 1 repeatedly
--				Changed the delay of character writes
------------------------------------------------------------------


library IEEE;
library work;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use IEEE.NUMERIC_STD.ALL;


	
entity lcd is
    Port ( LCD_DB: out std_logic_vector(7 downto 0);		--DB( 7 through 0)
           RS:out std_logic;  				--WE
           RW:out std_logic;				--ADR(0)
	   CLK:in std_logic;				--GCLK2
	   --ADR1:out std_logic;				--ADR(1)
	   --ADR2:out std_logic;				--ADR(2)
	   --CS:out std_logic;				--CSC
	   OE:out std_logic;				--OE
	   rst:in std_logic;				--BTN
	   --rdone: out std_logic);			--WriteDone output to work with DI05 test
		--teclado
		ps2d,ps2c:in std_logic
		);
end lcd;

architecture Behavioral of lcd is
			    
------------------------------------------------------------------
--  Component Declarations
------------------------------------------------------------------
-- COMPONENTES DO TECLADO E DO CONVERSOR PARA ASCII
component kb_code is
generic(W_SIZE: integer:=2);  -- 2^W_SIZE words in FIFO
   port (
      clk, reset: in  std_logic;
      ps2d, ps2c: in  std_logic;
      rd_key_code: in std_logic;
      key_code: out std_logic_vector(7 downto 0);
      kb_buf_empty: out std_logic
   );
end component kb_code;

component key2ascii is
port (
	key_code: in std_logic_vector(7 downto 0);
      ascii_code: out std_logic_vector(7 downto 0)
);

end component key2ascii;

					

------------------------------------------------------------------
--  Local Type Declarations
-----------------------------------------------------------------
--  Symbolic names for all possible states of the state machines.

	--LCD control state machine
	type mstate is (					  
		stFunctionSet,		 			--Initialization states
		stDisplayCtrlSet,
		stDisplayClear,
		stPowerOn_Delay,  				--Delay states
		stFunctionSet_Delay,
		stDisplayCtrlSet_Delay, 	
		stDisplayClear_Delay,
		stInitDne,					--Display charachters and perform standard operations
		stActWr,
		stCharDelay					--Write delay for operations
		--stWait					--Idle state
	);

	--Write control state machine
	type wstate is (
		stRW,						--set up RS and RW
		stEnable,					--set up E
		stIdle						--Write data on DB(0)-DB(7)
	);
	
	-- Maquina de estados jogo da forca
	type gstate is (
		menu,         -- Define a tela inicial e seta/reseta algumas variaveis em caso de reset síncrono/assíncrono.
		menu_Delay,   -- Espera que o ponteiro do Display LCD escreva em todas as posições e retorne antes de ir ao prox. estado.
		playing,      -- Define e redefine o display de acordo com a progressão do jogador pressionando o teclado.
		gEnd,			  -- Se o jogador vencer o jogo (a palavra for descoberta) ou perder (vidas = 0) este estado mensageia o jogador.
		gEnd_delay    -- Este estado é responsável por fornecer o devido delay ao Display, para que a mensagem seja escrita. 
	);

	type gletter is (
		idlewait,     -- Espera que o jogador pressione uma tecla. 
		check,  		  -- Verifica a letra pressionada pelo jogador. 
		decide  	  -- Verfica se o jogador venceu o jogo ou perdeu o jogo, e atualiza o valor atual da vida. 
		);
		

------------------------------------------------------------------
--  Signal Declarations and Constants
------------------------------------------------------------------
	--These constants are used to initialize the LCD pannel.

	--FunctionSet:
		--Bit 0 and 1 are arbitrary
		--Bit 2:  Displays font type(0=5x8, 1=5x11)
		--Bit 3:  Numbers of display lines (0=1, 1=2)
		--Bit 4:  Data length (0=4 bit, 1=8 bit)
		--Bit 5-7 are set
	--DisplayCtrlSet:
		--Bit 0:  Blinking cursor control (0=off, 1=on)
		--Bit 1:  Cursor (0=off, 1=on)
		--Bit 2:  Display (0=off, 1=on)
		--Bit 3-7 are set
	--DisplayClear:
		--Bit 1-7 are set	
	signal clkCount:std_logic_vector(5 downto 0) := "000000";
	signal activateW:std_logic:= '0';		    			--Activate Write sequence
	signal count:std_logic_vector (16 downto 0):= "00000000000000000";	--15 bit count variable for timing delays
	signal delayOK:std_logic:= '0';						--High when count has reached the right delay time
	signal OneUSClk:std_logic := '0';						--Signal is treated as a 1 MHz clock	
	signal stCur:mstate:= stPowerOn_Delay;					--LCD control state machine
	signal stNext:mstate;			  	
	signal stCurW:wstate:= stIdle; 						--Write control state machine
	signal stNextW:wstate;
	signal writeDone:std_logic:= '0';					--Command set finish
	
	-- SINAIS DO JOGO DA FORCA -- 
	
	signal word:std_logic_vector(5 downto 0):=(others =>'0'); -- palavra secreta
	signal letter:std_logic_vector(7 downto 0); 					 -- letra para conversao para ascii
   signal vidas: std_logic_vector(2 downto 0):= "101";       -- Inteiro correspondente às vidas do jogador
	
	-- Sinais que mostram ao jogador os tracos na tela
	-- também responsáveis por mostrar ao jogador as letras 
	-- acertadas, sendo atualizados pela máq. de estados gletter. 
	signal L1:std_logic_vector(7 downto 0):= x"5f"; -- _       
	signal L2:std_logic_vector(7 downto 0):= x"5f"; -- _
	signal L3:std_logic_vector(7 downto 0):= x"5f"; -- _
	signal L4:std_logic_vector(7 downto 0):= x"5f"; -- _
	signal L5:std_logic_vector(7 downto 0):= x"5f"; -- _
	
	
	-- Sinais responsaveis pelo controle da maquina de estados
	signal nxState:gstate;             --Váriavel de estados responsáveis pela interface visível.
	signal crState:gstate:= menu;		  --Define o estado inicial como "menu".
   signal delayTR:std_logic:= '0';	  --Fornece o tempo necessário para que o jogador leia a mensagem de vitória/derrota.
	signal delay:std_logic:= '0';		  --Indica que o LCD escreveu todas as posições iniciais à serem utilizadas (0-12).
	signal counter:std_logic_vector (21 downto 0):= "0000000000000000000000"; --Contador que fornece delay para leitura até rst.
	-- Sinais responsaveis pelo controle da maquina de estados
	signal nxLstate:gletter; 			  --Váriavel de estados responsáveis pela verificação das letras pressionadas.
	signal crLstate:gletter:= idlewait;-- Define o estádo inicial como "idlewait".
	
	-- Sinais do teclado e conversor 
	signal rd_key_code: std_logic:= '0'; --Limpa "key_code" e "kb_buf_empty" quando rd_key_code'event.
   signal key_code: std_logic_vector(7 downto 0);
	signal kb_buf_empty: std_logic;

	type LCD_CMDS_T is array(integer range 0 to 25) of std_logic_vector(9 downto 0); -- Define os valores padrões do Display LCD.
	signal LCD_CMDS : LCD_CMDS_T := ( 
						 0 => "00"&X"3C",			--Function Set
					    1 => "00"&X"0E",			--Display ON, Cursor ON, Blink OFF, Decidimos por habilitar o cursor.
					    2 => "00"&X"01",			--Clear Display
					    3 => "00"&X"02", 			--return home
						 
						 -- Valores padrão somente modificados para constar o nome "Jogo da forca" no projeto
						 -- Apesar de termos 25 posições declaradas, ao inicializarmos nossa máquina de estados 
						 -- Iteramos somente nas posições 4-12. que é o suficiente para aparecer os traçoes e 
						 -- a vida.
						 4 => "10"&X"4A", 			--J 
					    5 => "10"&X"4F",  			--O
					    6 => "10"&X"47",  			--G
					    7 => "10"&X"4F", 			--O
					    8 => "10"&X"20", 			--space
					    9 => "10"&X"44",  			--D
					    10 => "10"&X"41", 			--A
					    11 => "10"&X"20", 			--space
					    12 => "10"&X"46", 			--F
					    13 => "10"&X"4F", 			--O			
					    14 => "10"&X"52",			--R						
					    15 => "10"&X"43", 			--C
					    16 => "10"&X"41", 			--A
						 
					    17 => "00"&X"c0", 			--Pula linha
						 
					    18 => "10"&X"41", 			--A
					    19 => "10"&X"50", 			--P
					    20 => "10"&X"45", 			--E
					    21 => "10"&X"52", 			--R
					    22 => "10"&X"54",			--T
					    23 => "10"&X"45",			--E
						 24 => "10"&X"20", 			--
					    25 => "00"&X"02"				--return home
						 );			

													
	signal lcd_cmd_ptr : integer range 0 to 25 := 0;
begin

	--  This process counts to 50, and then resets.  It is used to divide the clock signal time.
	process (CLK, oneUSClk)
    		begin
			if (CLK = '1' and CLK'event) then
				clkCount <= clkCount + 1;
			end if;
		end process;
	--  This makes oneUSClock peak once every 1 microsecond

	oneUSClk <= clkCount(5);
	--  This process incriments the count variable unless delayOK = 1.
	process (oneUSClk, delayOK)
		begin
			if (oneUSClk = '1' and oneUSClk'event) then
				if delayOK = '1' then
					count <= "00000000000000000";
				else
					count <= count + 1;
				end if;
			end if;
		end process;

	--This goes high when all commands have been run
	writeDone <= '1' when (lcd_cmd_ptr = 25) 
		else '0';
	--rdone <= '1' when stCur = stWait else '0';
	--Increments the pointer so the statemachine goes through the commands
	process (lcd_cmd_ptr, oneUSClk)
   		begin
			if (oneUSClk = '1' and oneUSClk'event) then
				if ((stNext = stInitDne or stNext = stDisplayCtrlSet or stNext = stDisplayClear) and writeDone = '0') then 
					lcd_cmd_ptr <= lcd_cmd_ptr + 1;
				elsif stCur = stPowerOn_Delay or stNext = stPowerOn_Delay then
					lcd_cmd_ptr <= 0;
				elsif lcd_cmd_ptr = 12 then -- Se o ponteiro alcançar a posição 12, ele retorna para a posição 3 (return_home).
				 lcd_cmd_ptr <= 3;										
				else															 
					lcd_cmd_ptr <= lcd_cmd_ptr;
				end if;
			end if;
		end process;
	
	--  Determines when count has gotten to the right number, depending on the state.

	delayOK <= '1' when ((stCur = stPowerOn_Delay and count = "00100111001010010") or 			--20050  
					(stCur = stFunctionSet_Delay and count = "00000000000110010") or	--50
					(stCur = stDisplayCtrlSet_Delay and count = "00000000000110010") or	--50
					(stCur = stDisplayClear_Delay and count = "00000011001000000") or	--1600
					(stCur = stCharDelay and count = "11111111111111111"))			--Max Delay for character writes and shifts
					--(stCur = stCharDelay and count = "00000000000100101"))		--37  This is proper delay between writes to ram.
		else	'0';
  	
	-- This process runs the LCD status state machine
	process (oneUSClk, rst)
		begin
			if oneUSClk = '1' and oneUSClk'Event then
				if rst = '1' then
					stCur <= stPowerOn_Delay;
				else
					stCur <= stNext;
				end if;
			end if;
		end process;

	-- Estes processos sao responsaveis por inicializar o LCD com o devido delay
	--  This process generates the sequence of outputs needed to initialize and write to the LCD screen
	process (stCur, delayOK, writeDone, lcd_cmd_ptr)
		begin   
				-- Esta máquina de estados é responsável por inicializar o displat LCD.
			case stCur is
			
				--  Delays the state machine for 20ms which is needed for proper startup.
				when stPowerOn_Delay =>
					if delayOK = '1' then
						stNext <= stFunctionSet;
					else
						stNext <= stPowerOn_Delay;
					end if;
					RS <= LCD_CMDS(lcd_cmd_ptr)(9);
					RW <= LCD_CMDS(lcd_cmd_ptr)(8);
					LCD_DB <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
					activateW <= '0';

				-- This issuse the function set to the LCD as follows 
				-- 8 bit data length, 2 lines, font is 5x8.
				when stFunctionSet =>
					RS <= LCD_CMDS(lcd_cmd_ptr)(9);
					RW <= LCD_CMDS(lcd_cmd_ptr)(8);
					LCD_DB <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
					activateW <= '1';	
					stNext <= stFunctionSet_Delay;
				
				--Gives the proper delay of 37us between the function set and
				--the display control set.
				when stFunctionSet_Delay =>
					RS <= LCD_CMDS(lcd_cmd_ptr)(9);
					RW <= LCD_CMDS(lcd_cmd_ptr)(8);
					LCD_DB <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
					activateW <= '0';
					if delayOK = '1' then
						stNext <= stDisplayCtrlSet;
					else
						stNext <= stFunctionSet_Delay;
					end if;
				
				--Issuse the display control set as follows
				--Display ON,  Cursor OFF, Blinking Cursor OFF.
				when stDisplayCtrlSet =>
					RS <= LCD_CMDS(lcd_cmd_ptr)(9);
					RW <= LCD_CMDS(lcd_cmd_ptr)(8);
					LCD_DB <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
					activateW <= '1';
					stNext <= stDisplayCtrlSet_Delay;

				--Gives the proper delay of 37us between the display control set
				--and the Display Clear command. 
				when stDisplayCtrlSet_Delay =>
					RS <= LCD_CMDS(lcd_cmd_ptr)(9);
					RW <= LCD_CMDS(lcd_cmd_ptr)(8);
					LCD_DB <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
					activateW <= '0';
					if delayOK = '1' then
						stNext <= stDisplayClear;
					else
						stNext <= stDisplayCtrlSet_Delay;
					end if;
				
				--Issues the display clear command.
				when stDisplayClear	=>
					RS <= LCD_CMDS(lcd_cmd_ptr)(9);
					RW <= LCD_CMDS(lcd_cmd_ptr)(8);
					LCD_DB <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
					activateW <= '1';
					stNext <= stDisplayClear_Delay;

				--Gives the proper delay of 1.52ms between the clear command
				--and the state where you are clear to do normal operations.
				when stDisplayClear_Delay =>
					RS <= LCD_CMDS(lcd_cmd_ptr)(9);
					RW <= LCD_CMDS(lcd_cmd_ptr)(8);
					LCD_DB <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
					activateW <= '0';
					if delayOK = '1' then
						stNext <= stInitDne;
					else
						stNext <= stDisplayClear_Delay;
					end if;
				
				-- A partir daqui o LCD alterna entre estes 3 estados escrevendo e lendo 
				-- os dados no LCD.
				
				--State for normal operations for displaying characters, changing the
				--Cursor position etc.
				when stInitDne =>		
					RS <= LCD_CMDS(lcd_cmd_ptr)(9);
					RW <= LCD_CMDS(lcd_cmd_ptr)(8);
					LCD_DB <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
					activateW <= '0';
					stNext <= stActWr;

				when stActWr =>		
					RS <= LCD_CMDS(lcd_cmd_ptr)(9);
					RW <= LCD_CMDS(lcd_cmd_ptr)(8);
					LCD_DB <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
					activateW <= '1';
					stNext <= stCharDelay;
					
				--Provides a max delay between instructions.
				when stCharDelay =>
					RS <= LCD_CMDS(lcd_cmd_ptr)(9);
					RW <= LCD_CMDS(lcd_cmd_ptr)(8);
					LCD_DB <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
					activateW <= '0';					
					if delayOK = '1' then
						stNext <= stInitDne;
					else
						stNext <= stCharDelay;
					end if;
			end case;
		
		end process;					
	
	--Esse processo inicializa a escrita na maquina de estados
 	--This process runs the write state machine
	process (oneUSClk, rst)
		begin
			if oneUSClk = '1' and oneUSClk'Event then
				if rst = '1' then
					stCurW <= stIdle;
				else
					stCurW <= stNextW;
				end if;
			end if;
		end process;

	--This genearates the sequence of outputs needed to write to the LCD screen
	process (stCurW, activateW)
		begin   
		
			case stCurW is
				--This sends the address across the bus telling the DIO5 that we are
				--writing to the LCD, in this configuration the adr_lcd(2) controls the
				--enable pin on the LCD
				when stRw =>
					OE <= '0';
					--CS <= '0';
					--ADR2 <= '1';
					--ADR1 <= '0';
					stNextW <= stEnable;
				
				--This adds another clock onto the wait to make sure data is stable on 
				--the bus before enable goes low.  The lcd has an active falling edge 
				--and will write on the fall of enable
				when stEnable => 
					OE <= '0';
					--CS <= '0';
					--ADR2 <= '0';
					--ADR1 <= '0';
					stNextW <= stIdle;
				
				--Waiting for the write command from the instuction state machine
				when stIdle =>
					--ADR2 <= '0';
					--ADR1 <= '0';
					--CS <= '1';
					OE <= '1';
					if activateW = '1' then
						stNextW <= stRw;
					else
						stNextW <= stIdle;
					end if;
				end case;
		end process;
	 
	 -- Declara kb_code e key2ascii
	 teclado : kb_code port map(CLK => OneUSClk,reset => rst,ps2c => ps2c,ps2d => ps2d,rd_key_code => rd_key_code,key_code => key_code,kb_buf_empty => kb_buf_empty);
	 conversor : key2ascii port map(key_code => key_code,ascii_code =>letter);
		
		-- Processo responsável por incrementar o contador fornecendo o tempo necessário para o jogador ler a mensagem final.
	 process (OneUSClk, delayTR)
		begin
			if (OneUSClk = '1' and OneUSClk'event) then
				if delayTR = '1' then
					counter <= "0000000000000000000000";
				else
					counter <= counter + 1;
				end if;
			end if;
	 end process;
		
		-- Esta parte do código atribui os delays para cada estado -- 
		
    delayTR <= '1' when	((crState = gEnd_delay and counter = "1111111111111111111111")) 
		else	'0';	
		
	 delay <= '1' when ((crState = menu_Delay and lcd_cmd_ptr = 12) or 
							  (crLstate = decide and lcd_cmd_ptr = 3))
		else	'0';
	 
	 
	 
	-- Inicializa o jogo da forca e define um reset assíncrono--
	 process(oneUSClk,rst)
	 begin
	 if (oneUSClk = '1' and oneUSClk'Event) then
		if rst = '1' then
			crState <= menu;
		else
			crState <= nxState;
		end if;
	 end if;
	 end process;

	 
	 -- Inicializa os processos da maquina de estados jogo da forca -- 
	 -- Esse processo é responsável por definir os valores da interface do display LCD
	 
	 process(crState,L1,L2,L3,L4,L5,word,vidas,delay)
	 begin
	 
	 
	 case crState is 
	 -- Menu define as variáveis iniciais escrevendo da posição 4 até a posição 12
	 -- Com excessão da posição 11 que será definido apenas na outra maq de estados 
	 when menu =>
	 LCD_CMDS(4) <= "10"&L1; 			--_
	 LCD_CMDS(5) <= "10"&L2;  			--_
	 LCD_CMDS(6) <= "10"&L3;  			--_
	 LCD_CMDS(7) <= "10"&L4; 			--_
	 LCD_CMDS(8) <= "10"&L5; 			--_
	 LCD_CMDS(9) <= "10"&x"20";  			--space
	 LCD_CMDS(10) <= "10"&x"20"; 			--space

	 nxState <= menu_Delay;
	 
	 -- Menu_delay é responsável por aguardar o ponteiro escrever todas as variáveis do menu 
	 -- Para só então liberar o próximo estado. 
	 when menu_Delay =>
	 if delay = '1' then
	 nxState <= playing;
	 else
	 nxState <= menu_Delay;
	 end if;
	 
	 -- No estado playing temos nosso estado "estático" onde nosso jogador visualizará os traços
	 -- e sua vida. E a medida que haja erros ou acertos, aparecerá as letras correspondentes aos acertos
	 -- e a vida diminuirá de acordo com os erros.
    when playing =>
	 -- O estado playing espera que uma letra seja pressionada.
	 LCD_CMDS(4) <= "10"&L1; 			--_
	 LCD_CMDS(5) <= "10"&L2;  			--_
	 LCD_CMDS(6) <= "10"&L3;  			--_
	 LCD_CMDS(7) <= "10"&L4; 			--_
	 LCD_CMDS(8) <= "10"&L5; 			--_
	 LCD_CMDS(9) <= "10"&X"20";  			--space
	 LCD_CMDS(10) <= "10"&x"2c"; 			--space
	 
	 nxState <= gEnd;
	
	-- gEnd é o estado responsável por verificar se o jogador venceu ou perdeu, temos duas verificações 
	-- Se a palavra foi completamente descoberta, ou se a variavel vidas é igual a 0.
	-- Caso contrário sempre voltamos para o estado playing.
	when gEnd =>
	 if word = "111111" then
		 
		 LCD_CMDS(4) <= "10"&x"47";
		 LCD_CMDS(5) <= "10"&x"41";
		 LCD_CMDS(6) <= "10"&x"4E";
		 LCD_CMDS(7) <= "10"&x"48";
		 LCD_CMDS(8) <= "10"&x"4f";
		 LCD_CMDS(9) <= "10"&x"55";
		
		 nxState <= gEnd_Delay;

	 elsif vidas = 0 then
		 LCD_CMDS(4) <= "10"&x"50";
		 LCD_CMDS(5) <= "10"&x"45";
		 LCD_CMDS(6) <= "10"&x"52"; 
		 LCD_CMDS(7) <= "10"&x"44";
		 LCD_CMDS(8) <= "10"&x"45";
		 LCD_CMDS(9) <= "10"&x"55";
	
		 nxState <= gEnd_Delay;
	 else
		nxState<= playing;
	 end if;
	 
	 -- gEnd_delay é um estado que possui o delay necessário para que a mensagem de vitória ou derrota apareça na tela 
	 -- antes que o jogador seja redirecionado ao menu.
	 when gEnd_Delay =>
	 if delayTR= '1' then
		 nxState <= menu;
	 else
	 nxState <= gEnd_Delay;
	 end if;
	 
	 end case;
	 
	 end process;
	 
	  -- Inicializa o estado das teclas --
	 process(oneUSClk,rst,word,vidas)
	 begin
	 if (oneUSClk = '1' and oneUSClk'Event) then
		if rst = '1' then
			crLstate <= idlewait;
		else
			crLstate <= nxLstate;
		end if;
	 end if;
	 end process;
	 
	-- Máquina de estados responsável por receber a tecla pressionada no teclado 
	-- e avaliar se ela pertence ou não à palavra, de modo a alterar os sinais 
	-- correspondentes à inicialmente os traços e também a diminuir a vida, a medida 
	-- que haja error. 
	process(crLstate,letter,word,vidas,L1,L2,L3,L4,L5,word,rd_key_code,kb_buf_empty)
	begin
	
	 case crLstate is
		-- Idlewait espera que uma tecla seja pressionada para ir ao proximo estado.
		 when idlewait =>

			if kb_buf_empty = '0' and rd_key_code = '0'  then 
				nxLstate<=check;
			else
				nxLstate<=idlewait;
			end if;
			
		-- Check é responsável por verificar se a letra pertence ou não á palavra
		-- Para que haja a verificação há uma condição, que a letra pertença à uma 
		-- das letras convertidas de ASCII
		 when check =>
		 -- O estado check verifica se a letra pressionada pelo jogador foi certa ou errada,
		 -- Se a letra não pertencer à nenhuma das letras incluidas no case letter
		 -- A vida do jogador é reduzida em 1, caso o contrário, o jogador vai para o estado decide.
		 
		 -- É importante que o rd_key_code receba '1', pois precisamos receber uma nova letra. 
		 if letter /= "00101010" then
				case letter is
					when "01011001" =>
							word(0) <= '1';
							L1 <= x"59";
							nxLstate <= decide;
							rd_key_code <= '1';
					when "01001111" => 
							word(1) <= '1';
							L2 <= x"4f";
							nxLstate <= decide;
							rd_key_code <= '1';
					when "01010011" =>
							word(2) <= '1'; 
							L3 <= x"53";
							nxLstate <= decide;
							rd_key_code <= '1';
					when "01001000" =>
							word(3) <= '1';
							L4 <= x"48";
							nxLstate <= decide;
							rd_key_code <= '1';
					when "01001001" => 
							word(4) <= '1';
							L5 <= x"49";
							nxLstate <= decide;
							rd_key_code <= '1';
					when others =>
						nxLstate <= decide;
						vidas <= vidas - 1;
						rd_key_code <= '1';
					end case;
			else 
				nxLstate <= check;
			end if;
			
			-- decide é o estado responsável por finalizar o jogo,
			-- Ele verifica se a palavra foi descoberta, então vai para o estado inicial,
			-- caso o contrário ele atualiza a vida e passa para o próximo estado.
			when decide => 
				if (word = "011111") then 
						word(5) <= '1';
						nxLstate <= idlewait;
						rd_key_code <= '0';
				else
					case vidas is 
						when "101" =>
							LCD_CMDS(11) <= "10"&x"35";
							nxLstate <= idlewait;
						   rd_key_code <= '0';
						when "100" =>
							LCD_CMDS(11) <= "10"&x"34";
							nxLstate <= idlewait;
						   rd_key_code <= '0';
						when "011" =>
							LCD_CMDS(11) <= "10"&x"33";
							nxLstate <= idlewait;
						   rd_key_code <= '0';
						when "010" =>
							LCD_CMDS(11) <= "10"&x"32";
							nxLstate <= idlewait;
						   rd_key_code <= '0';
						when "001" =>
							LCD_CMDS(11) <= "10"&x"31";
							nxLstate <= idlewait;
						   rd_key_code <= '0';
						when "000" =>
							LCD_CMDS(11) <= "10"&x"30";
							nxLstate <= idlewait;
						   rd_key_code <= '0';
						when others =>
							nxLstate <= idlewait;
						   rd_key_code <= '0';
					 end case;
				end if;
	
		end case;
		end process;
end Behavioral;
	 
