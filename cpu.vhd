-- cpu.vhd: Simple 8-bit CPU (BrainFuck interpreter)
-- Copyright (C) 2024 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): Jakub Lůčný <xlucnyj00 AT stud.fit.vutbr.cz>
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity cpu is
 port (
   CLK   : in std_logic;  -- hodinovy signal
   RESET : in std_logic;  -- asynchronni reset procesoru
   EN    : in std_logic;  -- povoleni cinnosti procesoru
 
   -- synchronni pamet RAM
   DATA_ADDR  : out std_logic_vector(12 downto 0); -- adresa do pameti
   DATA_WDATA : out std_logic_vector(7 downto 0); -- mem[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
   DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
   DATA_RDWR  : out std_logic;                    -- cteni (1) / zapis (0)
   DATA_EN    : out std_logic;                    -- povoleni cinnosti
   
   -- vstupni port
   IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA <- stav klavesnice pokud IN_VLD='1' a IN_REQ='1'
   IN_VLD    : in std_logic;                      -- data platna
   IN_REQ    : out std_logic;                     -- pozadavek na vstup data
   
   -- vystupni port
   OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
   OUT_BUSY : in std_logic;                       -- LCD je zaneprazdnen (1), nelze zapisovat
   OUT_INV  : out std_logic;                      -- pozadavek na aktivaci inverzniho zobrazeni (1)
   OUT_WE   : out std_logic;                      -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'

   -- stavove signaly
   READY    : out std_logic;                      -- hodnota 1 znamena, ze byl procesor inicializovan a zacina vykonavat program
   DONE     : out std_logic                       -- hodnota 1 znamena, ze procesor ukoncil vykonavani programu (narazil na instrukci halt)
 );
end cpu;


-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
architecture behavioral of cpu is

 -- pri tvorbe kodu reflektujte rady ze cviceni INP, zejmena mejte na pameti, ze 
 --   - nelze z vice procesu ovladat stejny signal,
 --   - je vhodne mit jeden proces pro popis jedne hardwarove komponenty, protoze pak
 --      - u synchronnich komponent obsahuje sensitivity list pouze CLK a RESET a 
 --      - u kombinacnich komponent obsahuje sensitivity list vsechny ctene signaly.

-------------------------- Used signals ---------------------------
    ----- pc_reg -----
    signal pc_inc : std_logic;
    signal pc_dec : std_logic;
    signal pc_out : std_logic_vector(12 downto 0);

    ----- ptr_reg -----
    signal ptr_inc : std_logic;
    signal ptr_dec : std_logic;
    signal ptr_out : std_logic_vector(12 downto 0);
    signal ptr_rst : std_logic;

    ----- tmp_reg -----
    signal tmp_ld : std_logic;
    signal tmp_out : std_logic_vector(7 downto 0);

    ----- cnt_reg ------
    signal cnt_inc : std_logic;
    signal cnt_dec : std_logic;
    signal cnt_out : std_logic_vector(7 downto 0);

    ----- mxs -----
    signal mx1_sel : std_logic;
    signal mx2_sel : std_logic_vector(1 downto 0);

----------------------------- FSM --------------------------------
    type t_state is (
        START1,
        START2,

        FETCH,
        DECODE,

        INC_PTR,
        DEC_PTR,

        INC_VAL1,
        INC_VAL2,

        DEC_VAL1,
        DEC_VAL2,

        WHILE_START1,
        WHILE_START2,
        SKIPPIN_TIME1,
        SKIPPIN_TIME2,
        SKIPPIN_TIME3,

        WHILE_END1,
        WHILE_END2,
        COMEBACK_TIME1,
        COMEBACK_TIME2,
        COMEBACK_TIME3,

        SAVE_TMP1,
        SAVE_TMP2,

        LOAD_FROM_TMP,

        PRINT1,
        PRINT2,

        READ1,

        HALT,
        IGNORE
    );

    signal state : t_state;
    signal next_state : t_state;

begin
------------------------- PC_reg -----------------------------
    pc_reg_p: process(CLK, RESET)
    begin
        if RESET = '1' then
            pc_out <= (others => '0');
        elsif rising_edge(CLK) then
            if pc_inc = '1' then
                pc_out <= pc_out + 1;
            elsif pc_dec = '1' then
                pc_out <= pc_out - 1;
            end if;
        end if;
    end process pc_reg_p;

--------------------------- PTR_reg ---------------------------
    ptr_reg_p: process(CLK, RESET)
    begin
        if RESET = '1' then
            ptr_out <= (others => '0');
        elsif rising_edge(CLK) then
            -- make sure it works as cyclic buffer
            if ptr_inc = '1' then
                if ptr_out = "1111111111111" then
                    ptr_out <= "0000000000000";
                else
                    ptr_out <= ptr_out + 1;
                end if;
            
            elsif ptr_dec = '1' then
                if ptr_out = "0000000000000" then
                    ptr_out <= "1111111111111";
                else
                    ptr_out <= ptr_out - 1;
                end if;

            elsif ptr_rst = '1' then
                ptr_out <= (others => '0');

            end if;
        end if;
    end process ptr_reg_p;

---------------------------- TMP_reg --------------------------
    tmp_reg_p: process(CLK, RESET)
    begin
        if RESET = '1' then
            tmp_out <= (others => '0');
        elsif rising_edge(CLK) and tmp_ld = '1' then    -- on rising edge, when load is activated
            tmp_out <= DATA_RDATA;
        end if;
    end process tmp_reg_p;

---------------------------- CNT_reg --------------------------
    cnt_reg_p: process(CLK, RESET)
    begin
        if RESET = '1' then
            cnt_out <= (others => '0');
        elsif rising_edge(CLK) then
            if cnt_inc = '1' then
                cnt_out <= cnt_out + 1;
            elsif cnt_dec = '1' then
                cnt_out <= cnt_out - 1;
            end if;
        end if;
    end process cnt_reg_p;

----------------------------- MX1 -----------------------------
    mx1_p : process (mx1_sel, ptr_out, pc_out)
    begin
        case (mx1_sel) is
            when '0' => DATA_ADDR <= ptr_out;
            when '1' => DATA_ADDR <= pc_out;
            when others =>
        end case;
    end process mx1_p;

----------------------------- MX2 -----------------------------
    mx2_p : process (mx2_sel, IN_DATA, tmp_out, DATA_RDATA)
    begin
        case (mx2_sel) is
            when "00" => DATA_WDATA <= IN_DATA;
            when "01" => DATA_WDATA <= tmp_out;
            when "10" => DATA_WDATA <= DATA_RDATA - 1;
            when "11" => DATA_WDATA <= DATA_RDATA + 1;
            when others =>
        end case;
    end process mx2_p;

------------------ Register for current state ------------------
    state_reg_p : process (CLK, RESET)
    begin
        if RESET = '1' then
            state <= START1;
        elsif rising_edge(CLK) then
            if EN = '1' then
                state <= next_state;
            end if;
        end if;
    end process state_reg_p;


---------------------- NEXT STATE LOGIC -----------------------
    next_state_logic_p : process (CLK, EN, state, DATA_RDATA, IN_VLD, OUT_BUSY)
    begin
        ------ default values -------
        READY <= '1';
        DONE <= '0';

        DATA_EN <= '0';
        DATA_RDWR <= '0';

        mx1_sel <= '0';
        mx2_sel <= "00";

        pc_inc <= '0';
        pc_dec <= '0';

        ptr_rst <= '0';
        ptr_inc <= '0';
        ptr_dec <= '0';

        tmp_ld <= '0';

        cnt_inc <= '0';
        cnt_dec <= '0';

        IN_REQ <= '0';
        OUT_WE <= '0';
        OUT_INV <= '0';


        case (state) is
            -- initialize ptr
            when START1 =>
                READY <= '0';
                DATA_EN <= '1';
                DATA_RDWR <= '1';
                next_state <= START2;

            when START2 =>
                -- after we find '@' and set ptr, we can start executing instructions
                if DATA_RDATA = X"40" then -- hexadecimal ascii value of '@'
                    ptr_inc <= '1';
                    READY <= '1';
                    next_state <= FETCH;
                else
                    ptr_inc <= '1';
                    next_state <= START1;
                end if;


            when FETCH =>
                mx1_sel <= '1';     -- pc_out
                DATA_EN <= '1';
                DATA_RDWR <= '1';
                next_state <= DECODE;

            when DECODE =>
                case (DATA_RDATA) is
                    when X"3E" => next_state <= INC_PTR; -- >
                    when X"3C" => next_state <= DEC_PTR; -- <
                    when X"2B" => next_state <= INC_VAL1; -- +
                    when X"2D" => next_state <= DEC_VAL1; -- -
                    when X"5B" => next_state <= WHILE_START1; -- [
                    when X"5D" => next_state <= WHILE_END1; -- ]
                    when X"24" => next_state <= SAVE_TMP1; -- $
                    when X"21" => next_state <= LOAD_FROM_TMP; -- !
                    when X"2E" => next_state <= PRINT1; -- .
                    when X"2C" => next_state <= READ1; -- ,
                    when X"40" => next_state <= HALT; -- @
                    when others => next_state <= IGNORE;  -- other symbols, like comments or invalid symbols...
                end case;

            -- ptr += 1
            when INC_PTR =>
                ptr_inc <= '1';
                pc_inc <= '1';
                next_state <= FETCH;

            -- ptr -= 1
            when DEC_PTR =>
                ptr_dec <= '1';
                pc_inc <= '1';
                next_state <= FETCH;

            -- *ptr += 1
            when INC_VAL1 =>
                mx1_sel <= '0';
                DATA_EN <= '1';
                DATA_RDWR <= '1';
                next_state <= INC_VAL2;

            when INC_VAL2 =>
                mx2_sel <= "11";
                mx1_sel <= '0';
                DATA_EN <= '1';
                DATA_RDWR <= '0';
                pc_inc <= '1';
                next_state <= FETCH;

            -- *ptr -= 1
            when DEC_VAL1 =>
                mx1_sel <= '0';
                DATA_EN <= '1';
                DATA_RDWR <= '1';
                next_state <= DEC_VAL2;

            when DEC_VAL2 =>
                mx2_sel <= "10";
                mx1_sel <= '0';
                DATA_EN <= '1';
                DATA_RDWR <= '0';
                pc_inc <= '1';
                next_state <= FETCH;

            -- tmp = *ptr
            when SAVE_TMP1 =>
                mx1_sel <= '0';
                DATA_EN <= '1';
                DATA_RDWR <= '1';
                next_state <= SAVE_TMP2;

            when SAVE_TMP2 =>
                tmp_ld <= '1';
                pc_inc <= '1';
                next_state <= FETCH;

            -- *ptr = tmp
            when LOAD_FROM_TMP =>
                mx1_sel <= '0';
                mx2_sel <= "01";    -- tmp
                DATA_EN <= '1';
                DATA_RDWR <= '0';
                pc_inc <= '1';
                next_state <= FETCH;

            -- putchar(*ptr)
            when PRINT1 =>
                mx1_sel <= '0';
                DATA_EN <= '1';
                DATA_RDWR <= '1';
                next_state <= PRINT2;
                
            when PRINT2 =>
                OUT_INV <= '0';
                if OUT_BUSY = '0' then
                    OUT_WE <= '1';
                    OUT_DATA <= DATA_RDATA;
                    pc_inc <= '1';
                    next_state <= FETCH;
                else
                    next_state <= PRINT1;
                end if;

            -- *ptr = getchar()
            when READ1 =>
                IN_REQ <= '1';
                if IN_VLD = '1' then
                    mx1_sel <= '0';
                    mx2_sel <= "00";    -- IN_DATA
                    DATA_EN <= '1';
                    DATA_RDWR <= '0';
                    pc_inc <= '1';
                    next_state <= FETCH;
                else
                    next_state <= READ1;
                end if;

            -- return
            when HALT =>
                DONE <= '1';
                next_state <= HALT;

            -- "comments"
            when IGNORE =>
                pc_inc <= '1';
                next_state <= FETCH;

------------------------ WHILE LOOPS ----------------------------
            when WHILE_START1 =>
                mx1_sel <= '0';
                DATA_EN <= '1';
                DATA_RDWR <= '1';        --- read current data at ptr
                next_state <= WHILE_START2;

            when WHILE_START2 =>
                if (DATA_RDATA = X"00") then -- go to loop to skip everything until correct ']'
                    pc_inc <= '1';
                    -- increase only when we are in the first while loop
                    -- when in nested while, dont increase
                    if cnt_out = X"00" then
                        cnt_inc <= '1';
                    end if;

                    next_state <= SKIPPIN_TIME1;
                else
                    cnt_inc <= '1';
                    pc_inc <= '1';
                    next_state <= FETCH;
                end if;

            when SKIPPIN_TIME1 =>
                mx1_sel <= '1';
                DATA_EN <= '1';
                DATA_RDWR <= '1';
                next_state <= SKIPPIN_TIME2;

            -- checks for '[' or ']' and changes "cnt" appropriately
            when SKIPPIN_TIME2 =>
                if DATA_RDATA = X"5B" then -- = '['
                    cnt_inc <= '1';
                elsif DATA_RDATA = X"5D" then  -- = ']'
                    cnt_dec <= '1';
                end if;

                next_state <= SKIPPIN_TIME3;

            -- checks if we found the correct ']'
            when SKIPPIN_TIME3 =>
                if cnt_out = X"00" then
                    pc_inc <= '1';
                    next_state <= FETCH;
                else
                    pc_inc <= '1';
                    next_state <= SKIPPIN_TIME1;
                end if;

        ----------------- Start of second part of while loops ---------------
            when WHILE_END1 =>
                mx1_sel <= '0';
                DATA_EN <= '1';
                DATA_RDWR <= '1';        --- read current data at ptr
                next_state <= WHILE_END2;
            
            when WHILE_END2 =>
                if (DATA_RDATA = X"00") then -- end of while loop
                    pc_inc <= '1';
                    if cnt_out /= X"00" then -- if != 0 -> fix counter after nested loop
                        cnt_dec <= '1';
                    end if;
                    next_state <= FETCH;
                else
                    pc_dec <= '1';
                    next_state <= COMEBACK_TIME1;
                end if;

            when COMEBACK_TIME1 =>
                mx1_sel <= '1';
                DATA_EN <= '1';
                DATA_RDWR <= '1';
                next_state <= COMEBACK_TIME2;

            -- checks for '[' or ']' and changes "cnt" appropriately
            when COMEBACK_TIME2 =>
                if DATA_RDATA = X"5B" then -- = '['
                    cnt_dec <= '1';
                elsif DATA_RDATA = X"5D" then  -- = ']'
                    cnt_inc <= '1';
                end if;

                next_state <= COMEBACK_TIME3;

            -- checks if we found the correct '['
            when COMEBACK_TIME3 =>
                if cnt_out = X"00" then
                    next_state <= FETCH;
                else
                    pc_dec <= '1';
                    next_state <= COMEBACK_TIME1;
                end if;

            when others =>

        end case;
    end process next_state_logic_p;
end behavioral;
