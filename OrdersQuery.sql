-- =========================================
-- 1. Vytvoření databáze
-- =========================================

CREATE DATABASE ObjednavkyDB;
GO

USE ObjednavkyDB;
GO

-- =========================================
-- 2. Tabulky
-- =========================================

CREATE TABLE Organizace (
    OrganizaceID INT IDENTITY(1,1) PRIMARY KEY,
    Nazev NVARCHAR(100) NOT NULL,
    Ulice NVARCHAR(100),
    Mesto NVARCHAR(100),
    PSC NVARCHAR(10),
    JeDodavatel BIT DEFAULT 0,
    JeOdberatel BIT DEFAULT 0,
    IC NVARCHAR(10),
    DIC NVARCHAR(20)
);
GO

CREATE TABLE Produkty (
    ProduktID INT IDENTITY(1,1) PRIMARY KEY,
    Nazev NVARCHAR(100) NOT NULL,
    KatalogoveCislo NVARCHAR(20),
    MernaJednotka NVARCHAR(20),
    Hmotnost DECIMAL(12,6)
);
GO

CREATE TABLE HlavickyObjednavky (
    ObjednavkaID INT IDENTITY(1,1) PRIMARY KEY,
    OrganizaceID INT NOT NULL,
    DatumObjednani DATETIME2,
    TerminDodani DATE,
    CelkovaCena DECIMAL(12,2) DEFAULT 0,
    Poznamka NVARCHAR(MAX),

    FOREIGN KEY (OrganizaceID) REFERENCES Organizace(OrganizaceID)
);
GO

CREATE TABLE PolozkyObjednavky (
    PolozkaID INT IDENTITY(1,1) PRIMARY KEY,
    ObjednavkaID INT NOT NULL,
    ProduktID INT NOT NULL,
    JednotkovaCena DECIMAL(16,6),
    Mnozstvi DECIMAL(14,4),
    CelkovaCena DECIMAL(12,2),

    FOREIGN KEY (ObjednavkaID) REFERENCES HlavickyObjednavky(ObjednavkaID),
    FOREIGN KEY (ProduktID) REFERENCES Produkty(ProduktID),

    CONSTRAINT UQ_Obj_Produkt UNIQUE (ObjednavkaID, ProduktID)
);
GO

CREATE TABLE DodavateleProduktu (
    ID INT IDENTITY(1,1) PRIMARY KEY,
    DodavatelID INT,
    ProduktID INT,
    CelkemObjednano DECIMAL(14,4),
    DatumPosledniObjednavky DATE,
    PosledniCena DECIMAL(16,6),

    FOREIGN KEY (DodavatelID) REFERENCES Organizace(OrganizaceID),
    FOREIGN KEY (ProduktID) REFERENCES Produkty(ProduktID),

    CONSTRAINT UQ_DP UNIQUE (DodavatelID, ProduktID)
);
GO

-- =========================================
-- 3. Procedura – hlavička vydané objednávky
-- =========================================

CREATE OR ALTER PROCEDURE VlozHlavickuObjednavky
    @OrganizaceID INT,
    @DatumObjednani DATETIME2,
    @TerminDodani DATE,
    @Poznamka NVARCHAR(MAX),
    @NovaID INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    --- Kontrola existenci organizace v tabulce Organizace
    IF NOT EXISTS (SELECT 1 FROM Organizace WHERE OrganizaceID = @OrganizaceID)
    BEGIN
        RAISERROR('Organizace neexistuje',16,1);
        RETURN;
    END

    INSERT INTO HlavickyObjednavky (OrganizaceID, DatumObjednani, TerminDodani, Poznamka)
    VALUES (@OrganizaceID, @DatumObjednani, @TerminDodani, @Poznamka);
    
    -- Získání nově vloženého ID
    SET @NovaID = SCOPE_IDENTITY();
END;
GO

-- =========================================
-- 4. Procedura – položka vydané objednávky
-- =========================================

CREATE OR ALTER PROCEDURE VlozPolozkuObjednavky
    @ObjednavkaID INT,
    @ProduktID INT,
    @Cena DECIMAL(16,6),
    @Mnozstvi DECIMAL(14,4)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Celkova DECIMAL(12,2);
    DECLARE @DodavatelID INT;
    DECLARE @Datum DATE;

    -- Kontrola existenci objednávky v tabulce HlavickyObjednavky
    IF NOT EXISTS (SELECT 1 FROM HlavickyObjednavky WHERE ObjednavkaID = @ObjednavkaID)
    BEGIN
        RAISERROR('Objednavka neexistuje',16,1);
        RETURN;
    END

    -- Kontrola existenci produktu v tabulce Produkty
    IF NOT EXISTS (SELECT 1 FROM Produkty WHERE ProduktID = @ProduktID)
    BEGIN
        RAISERROR('Produkt neexistuje',16,1);
        RETURN;
    END

    SET @Celkova = @Cena * @Mnozstvi;

    INSERT INTO PolozkyObjednavky (ObjednavkaID, ProduktID, JednotkovaCena, Mnozstvi, CelkovaCena)
    VALUES (@ObjednavkaID, @ProduktID, @Cena, @Mnozstvi, @Celkova);

    UPDATE HlavickyObjednavky SET CelkovaCena = CelkovaCena + @Celkova WHERE ObjednavkaID = @ObjednavkaID;

    SELECT @DodavatelID = OrganizaceID, @Datum = CAST(DatumObjednani AS DATE)
    FROM HlavickyObjednavky
    WHERE ObjednavkaID = @ObjednavkaID;

    IF EXISTS (SELECT 1 FROM DodavateleProduktu WHERE DodavatelID = @DodavatelID AND ProduktID = @ProduktID)
    BEGIN
        UPDATE DodavateleProduktu
        SET 
            CelkemObjednano = CelkemObjednano + @Mnozstvi,
            DatumPosledniObjednavky = @Datum,
            PosledniCena = @Cena
        WHERE DodavatelID = @DodavatelID AND ProduktID = @ProduktID;
    END
    ELSE
    BEGIN
        INSERT INTO DodavateleProduktu (
            DodavatelID,
            ProduktID,
            CelkemObjednano,
            DatumPosledniObjednavky,
            PosledniCena
        )
        VALUES (
            @DodavatelID,
            @ProduktID,
            @Mnozstvi,
            @Datum,
            @Cena
        );
    END
END;
GO

-- =========================================
-- 5. Indexy pro optimalizaci dotazů
-- =========================================

CREATE INDEX IX_HlavickyObjednavky_OrganizaceID
ON HlavickyObjednavky (OrganizaceID);

CREATE INDEX IX_PolozkyObjednavky_ObjednavkaID
ON PolozkyObjednavky (ObjednavkaID);

CREATE INDEX IX_PolozkyObjednavky_ProduktID
ON PolozkyObjednavky (ProduktID);
GO

-- =========================================
-- 6. Testovací data
-- =========================================

INSERT INTO Organizace (Nazev, Ulice, Mesto, PSC, JeDodavatel, JeOdberatel, IC, DIC)
VALUES 
    ('Firma A', 'Ulice 1', 'Město 1', '30012', 1, 1, '12345678', 'CZ1234567890'),
    ('Firma B', 'Ulice 2', 'Město 2', '30013', 1, 0, '12345679', 'CZ1234567891'),
    ('Firma C', 'Ulice 3', 'Město 3', '30014', 0, 1, '12345680', 'CZ1234567892');
GO

INSERT INTO Produkty (Nazev, KatalogoveCislo, MernaJednotka, Hmotnost)
VALUES
    ('Produkt 1', 'P001', 'kus', 5),
    ('Produkt 2', 'P002', 'sixpack', 3),
    ('Produkt 3', 'P003', 'kus', 4);
GO

-- =========================================
-- 7. Testování procedur při vložení validních dat
-- =========================================

DECLARE @ID INT;
DECLARE @DATE DATETIME2 = GETDATE();

EXEC VlozHlavickuObjednavky
    @OrganizaceID = 1,
    @DatumObjednani = @DATE,
    @TerminDodani = '2026-06-10',
    @Poznamka = N'Test objednavka',
    @NovaID = @ID OUTPUT;


EXEC VlozPolozkuObjednavky @ObjednavkaID = 1, @ProduktID = 1, @Cena = 50, @Mnozstvi = 2;
EXEC VlozPolozkuObjednavky @ObjednavkaID = 1, @ProduktID = 2, @Cena = 100, @Mnozstvi = 2;
GO

-- =========================================
-- 8. Kontrola vložených dat
-- =========================================

SELECT * FROM Organizace;
SELECT * FROM Produkty;
SELECT * FROM HlavickyObjednavky;
SELECT * FROM PolozkyObjednavky;
SELECT * FROM DodavateleProduktu;
GO

-- =========================================
-- 9. Testování procedur při vložení nevalidních dat
-- =========================================

-- DECLARE @ID INT;
-- DECLARE @DATE DATETIME2 = GETDATE();
   
-- EXEC VlozHlavickuObjednavky
--     @OrganizaceID = 5,
--     @DatumObjednani = @DATE,
--     @TerminDodani = '2026-06-10',
--     @Poznamka = N'Test objednavka',
--     @NovaID = @ID OUTPUT;
   
-- EXEC VlozPolozkuObjednavky @ObjednavkaID = 2, @ProduktID = 5, @Cena = 50, @Mnozstvi = 2;
-- EXEC VlozPolozkuObjednavky @ObjednavkaID = 1, @ProduktID = 5, @Cena = 100, @Mnozstvi = 2;
-- GO

-- Chyby při provádění dotazu z externího systemu:
-- Msg 50000, Level 16, State 1, Procedure VlozHlavickuObjednavky, Line 19 [Batch Start Line 242]
-- Organizace neexistuje
-- Msg 50000, Level 16, State 1, Procedure VlozPolozkuObjednavky, Line 22 [Batch Start Line 242]
-- Objednavka neexistuje
-- Msg 50000, Level 16, State 1, Procedure VlozPolozkuObjednavky, Line 29 [Batch Start Line 242]
-- Produkt neexistuje
