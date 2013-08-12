package com.mustwin.market;

import com.fasterxml.jackson.core.JsonParseException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.dataformat.yaml.YAMLFactory;
import com.yammer.dropwizard.json.ObjectMapperFactory;
import org.junit.Assert;
import org.junit.Test;

import java.io.File;
import java.io.IOException;

/**
 * User: spont200
 * Date: 8/11/13
 */
public class MarketConfigurationTest {

    @Test
    public void testYaml() throws IOException {
        File file = new File("market.yml");
        Assert.assertTrue(file.exists());
        ObjectMapperFactory objectMapperFactory = new ObjectMapperFactory();
        ObjectMapper mapper = objectMapperFactory.build(new YAMLFactory());
        mapper.readValue(file, MarketConfiguration.class);
        // should not throw error
    }
}
