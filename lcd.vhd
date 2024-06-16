library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity lcd is
    Port (
       ps2d, ps2c: in  std_logic;
       LCD_DB: out std_logic_vector(7 downto 0);		
       RS:out std_logic;                
       RW:out std_logic;                
       CLK:in std_logic;                
       OE:out std_logic;                
       KBE:out std_logic;               
       LEDS: out std_logic_vector(7 downto 0); 
       rst:in std_logic		
    );
end lcd;

architecture Behavioral of lcd is

component kb_code is
   generic(W_SIZE: integer:=2);  
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

type mstate is (stFunctionSet, stDisplayCtrlSet, stDisplayClear, stPowerOn_Delay, stFunctionSet_Delay, stDisplayCtrlSet_Delay, stDisplayClear_Delay, stInitDne, stActWr, stCharDelay);

type wstate is (stRW, stEnable, stIdle);

signal clkCount: std_logic_vector(5 downto 0);
signal activateW: std_logic:= '0';		    
signal count: std_logic_vector (16 downto 0):= "00000000000000000";	
signal delayOK: std_logic:= '0';						
signal OneUSClk: std_logic;						
signal stCur: mstate:= stPowerOn_Delay;					
signal stNext: mstate;			  	
signal stCurW: wstate:= stIdle; 						
signal stNextW: wstate;
signal writeDone: std_logic;					
signal rd_key_code: std_logic:= '0';
signal key_code: std_logic_vector(7 downto 0);
signal kb_buf_empty: std_logic;
signal tecla: std_logic_vector(7 downto 0); 
signal start: std_logic;
signal palavra_certa: std_logic_vector (4 downto 0) := "00000"; 

type LCD_CMDS_T is array(integer range 0 to 30) of std_logic_vector(9 downto 0);
signal LCD_CMDS: LCD_CMDS_T := ( -- X antes de um número significa que o numero está em hexadecimal
    0 => "00"&X"3C", 
    1 => "00"&X"0C", 
    2 => "00"&X"01", 
    3 => "00"&X"02", 
    4 => "10"&X"5F", 
    5 => "10"&X"5F", 
    6 => "10"&X"5F", 
    7 => "10"&X"5F", 
    8 => "10"&X"5F", 
    9 => "10"&X"20", 
    10 => "10"&X"20", 
    11 => "10"&X"20", 
    12 => "10"&X"20", 
    13 => "10"&X"20", 
    14 => "10"&X"20", 
    15 => "10"&X"20", 
    16 => "10"&X"20", 
    17 => "10"&X"35", 
    18 => "00"&X"C0", 
    19 => "10"&X"20", 
    20 => "10"&X"20", 
    21 => "10"&X"20", 
    22 => "10"&X"20", 
    23 => "10"&X"20", 
    24 => "10"&X"20", 
    25 => "10"&X"20", 
    26 => "10"&X"20", 
    27 => "10"&X"20", 
    28 => "10"&X"20", 
    29 => "10"&X"20", 
    30 => "00"&X"02" 
);

signal lcd_cmd_ptr: integer range 0 to LCD_CMDS'HIGH + 1 := 0;

begin

    label0: kb_code port map(CLK, rst, ps2d, ps2c, rd_key_code, key_code, kb_buf_empty);
    KBE <= kb_buf_empty;
    LEDS <= key_code;

    label1: key2ascii port map (key_code, tecla);

    process (CLK, oneUSClk)
    begin
        if (CLK = '1' and CLK'event) then
            clkCount <= clkCount + 1;
        end if;
    end process;

    oneUSClk <= clkCount(5);

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

    writeDone <= '1' when (lcd_cmd_ptr = LCD_CMDS'HIGH) else '0';

    process (lcd_cmd_ptr, oneUSClk)
    begin
        if (oneUSClk = '1' and oneUSClk'event) then
            if ((stNext = stInitDne or stNext = stDisplayCtrlSet or stNext = stDisplayClear) and writeDone = '0') then 
                lcd_cmd_ptr <= lcd_cmd_ptr + 1;
            elsif stCur = stPowerOn_Delay or stNext = stPowerOn_Delay then
                lcd_cmd_ptr <= 0;
            elsif lcd_cmd_ptr = 30 then
                lcd_cmd_ptr <= 3;
            else
                lcd_cmd_ptr <= lcd_cmd_ptr;
            end if;
        end if;
    end process;

    delayOK <= '1' when (
        (stCur = stPowerOn_Delay and count = "00100111001010010") or
        (stCur = stFunctionSet_Delay and count = "00000000000110010") or
        (stCur = stDisplayCtrlSet_Delay and count = "00000000000000010") or
        (stCur = stDisplayClear_Delay and count = "00000011001000000") or
        (stCur = stCharDelay and count = "11111111111111111")
    ) else '0';

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

    process (stCur, delayOK, writeDone, lcd_cmd_ptr)
    begin
        case stCur is
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

            when stFunctionSet =>
                RS <= LCD_CMDS(lcd_cmd_ptr)(9);
                RW <= LCD_CMDS(lcd_cmd_ptr)(8);
                LCD_DB <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
                activateW <= '1';	
                stNext <= stFunctionSet_Delay;

            when stFunctionSet_Delay =>
                RS <= LCD_CMDS(lcd_cmd_ptr)(9);
                RW <= LCD_CMDS(lcd_cmd_ptr)(8);
                LCD_DB <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
                activateW <= '0';
                if delayOK = '1' then
                    stNext <= stDisplayCtrlSet;
                else
                    stNext <= stFunctionSet_Delay;

            when stDisplayCtrlSet =>
                RS <= LCD_CMDS(lcd_cmd_ptr)(9);
                RW <= LCD_CMDS(lcd_cmd_ptr)(8);
                LCD_DB <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
                activateW <= '1';
                stNext <= stDisplayCtrlSet_Delay;

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

            when stDisplayClear =>
                RS <= LCD_CMDS(lcd_cmd_ptr)(9);
                RW <= LCD_CMDS(lcd_cmd_ptr)(8);
                LCD_DB <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
                activateW <= '1';
                stNext <= stDisplayClear_Delay;

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

            when stInitDne =>
                if (writeDone = '1') then
                    stNext <= stActWr;
                else
                    stNext <= stInitDne;
                end if;

            when stActWr =>
                if (delayOK = '1' and writeDone = '0') then
                    stNext <= stCharDelay;
                else
                    stNext <= stActWr;
                end if;
                RS <= LCD_CMDS(lcd_cmd_ptr)(9);
                RW <= LCD_CMDS(lcd_cmd_ptr)(8);
                LCD_DB <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
                activateW <= '1';

            when stCharDelay =>
                if (delayOK = '1') then
                    stNext <= stActWr;
                else
                    stNext <= stCharDelay;
                end if;
                RS <= LCD_CMDS(lcd_cmd_ptr)(9);
                RW <= LCD_CMDS(lcd_cmd_ptr)(8);
                LCD_DB <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
                activateW <= '0';

            when others =>
                stNext <= stPowerOn_Delay;
                RS <= '0';
                RW <= '0';
                LCD_DB <= "00000000";
                activateW <= '0';
        end case;
    end process;

    OE <= activateW;

    process(oneUSClk)
        variable vidas: integer := 5;
    begin
        if (oneUSClk = '1' and oneUSClk'Event) then
            if rst = '1' then
                palavra_certa <= "00000";
                vidas := 5;
                start <= '0';
                LCD_CMDS(4) <= "10"&X"5F"; -- _
                LCD_CMDS(5) <= "10"&X"5F"; -- _
                LCD_CMDS(6) <= "10"&X"5F"; -- _
                LCD_CMDS(7) <= "10"&X"5F"; -- _
                LCD_CMDS(8) <= "10"&X"5F"; -- _
                LCD_CMDS(17) <= "10"&X"35"; -- 5
            end if;

            if (kb_buf_empty = '1') then
                rd_key_code <= '0';
            end if;

            if (kb_buf_empty = '0') and (start = '0') then
                start <= '1';
                LCD_CMDS(4) <= "10"&X"5F"; -- _
                LCD_CMDS(5) <= "10"&X"5F"; -- _
                LCD_CMDS(6) <= "10"&X"5F"; -- _
                LCD_CMDS(7) <= "10"&X"5F"; -- _
                LCD_CMDS(8) <= "10"&X"5F"; -- _
                LCD_CMDS(17) <= "10"&X"35"; -- 5
                rd_key_code <= '1';
            end if; 

            if ((start = '1') and (vidas > 0) and (kb_buf_empty = '0') and (palavra_certa /= "11111")) then
                case tecla is
                    when X"59" => -- Y
                        if (palavra_certa(4) = '0') then -- Y _ _ _ _ (4 3 2 1 0 : 5 bits porque são 5 letras diferentes)
                            palavra_certa(4) <= '1';
                        end if;
                    when X"4F" => -- O
                        if (palavra_certa(3) = '0') then -- _ O _ _ _ 
                            palavra_certa(3) <= '1';
                        end if;
                    when X"53" => -- S
                        if (palavra_certa(2) = '0') then -- _ _ S _ _
                            palavra_certa(2) <= '1';
                        end if;
                    when X"48" => -- H
                        if (palavra_certa(1) = '0') then -- _ _ _ H _
                            palavra_certa(1) <= '1';
                        end if;
                    when X"49" => -- I
                        if (palavra_certa(0) = '0') then -- _ _ _ _ I
                            palavra_certa(0) <= '1';
                        end if;
                    when others =>
                        vidas := vidas - 1; -- decréscimo da vida quando errar
                end case;
                rd_key_code <= '1';
            end if;

            if (palavra_certa = "11111") then
                palavra_certa <= "11111";
            end if;

            if (palavra_certa(4) = '1') then
                LCD_CMDS(4) <= "10"&X"59"; -- Y
            else
                LCD_CMDS(4) <= "10"&X"5F";
            end if;

            if (palavra_certa(3) = '1') then
                LCD_CMDS(5) <= "10"&X"4F"; -- O
            else
                LCD_CMDS(5) <= "10"&X"5F";
            end if;

            if (palavra_certa(2) = '1') then
                LCD_CMDS(6) <= "10"&X"53"; -- S
            else
                LCD_CMDS(6) <= "10"&X"5F";
            end if;

            if (palavra_certa(1) = '1') then
                LCD_CMDS(7) <= "10"&X"48"; -- H
            else
                LCD_CMDS(7) <= "10"&X"5F";
            end if;

            if (palavra_certa(0) = '1') then
                LCD_CMDS(8) <= "10"&X"49"; -- I
            else
                LCD_CMDS(8) <= "10"&X"5F";
            end if;

            case vidas is
                when 0 =>
                    LCD_CMDS(17) <= "10"&X"30"; -- 0
                when 1 =>
                    LCD_CMDS(17) <= "10"&X"31"; -- 1
                when 2 =>
                    LCD_CMDS(17) <= "10"&X"32"; -- 2
                when 3 =>
                    LCD_CMDS(17) <= "10"&X"33"; -- 3
                when 4 =>
                    LCD_CMDS(17) <= "10"&X"34"; -- 4
                when others =>
                    LCD_CMDS(17) <= "10"&X"35"; -- 5
            end case;
        end if;
    end process;

end Behavioral;
