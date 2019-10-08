package com.brentvatne.exoplayer.latens;
import com.google.gson.annotations.SerializedName;

class LatensRegistration {
    @SerializedName("CustomerName")
    String customerName;

    @SerializedName("AccountName")
    String accountName;

    @SerializedName("PortalId")
    String portalId;

    @SerializedName("friendlyName")
    String friendlyName;

    @SerializedName("DeviceInfo")
    LatensDeviceInfo deviceInfo;
}
